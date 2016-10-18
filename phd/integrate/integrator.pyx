import numpy as np
cimport numpy as np

from libc.math cimport sqrt, fabs, fmin, pow

from ..mesh.mesh cimport Mesh
from ..riemann.riemann cimport RiemannBase
from ..utils.particle_tags import ParticleTAGS
from ..containers.containers cimport CarrayContainer
from ..utils.carray cimport DoubleArray, IntArray, LongLongArray, LongArray


cdef int Real = ParticleTAGS.Real

cdef class IntegrateBase:

    def __init__(self, CarrayContainer pc, Mesh mesh, RiemannBase riemann):
        """Constructor for the Integrator"""

        self.dim = mesh.dim
        self.mesh = mesh
        self.riemann = riemann
        self.pc = pc

        self.gamma = riemann.gamma

        cdef str field
        cdef dict flux_vars = {}
        for field in pc.named_groups['conserative']:
            flux_vars[field] = 'double'
        self.flux = CarrayContainer(var_dict=flux_vars)
        self.flux.named_groups['momentum'] = pc.named_groups['momentum']

        cdef dict state_vars = {}
        for field in pc.named_groups['primitive']:
            state_vars[field] = 'double'

        self.left_state  = CarrayContainer(var_dict=state_vars)
        self.left_state.named_groups['velocity'] = pc.named_groups['velocity']

        self.right_state = CarrayContainer(var_dict=state_vars)
        self.right_state.named_groups['velocity'] = pc.named_groups['velocity']

    def compute_time_step(self):
        return self._compute_time_step()

    def integrate(self, double dt, double t, int iteration_count):
        self._integrate(dt, t, iteration_count)

    cdef double _compute_time_step(self):
        msg = "IntegrateBase::compute_time_step called!"
        raise NotImplementedError(msg)

    cdef _integrate(self, double dt, double t, int iteration_count):
        msg = "IntegrateBase::_integrate called!"
        raise NotImplementedError(msg)


cdef class MovingMesh(IntegrateBase):

    def __init__(self, CarrayContainer pc, Mesh mesh, RiemannBase riemann, int regularize = 0, double eta = 0.25):
        """Constructor for the Integrator"""

        IntegrateBase.__init__(self, pc, mesh, riemann)

        self.regularize = regularize
        self.eta = eta

    cdef _integrate(self, double dt, double t, int iteration_count):
        """Main step routine"""

        # particle flag information
        cdef IntArray tags = self.pc.get_carray("tag")

        # face information
        cdef LongArray pair_i = self.mesh.faces.get_carray("pair-i")
        cdef LongArray pair_j = self.mesh.faces.get_carray("pair-j")
        cdef DoubleArray area = self.mesh.faces.get_carray("area")

        # particle values
        cdef DoubleArray m  = self.pc.get_carray("mass")
        cdef DoubleArray e  = self.pc.get_carray("energy")

        # flux values
        cdef DoubleArray fm  = self.flux.get_carray("mass")
        cdef DoubleArray fe  = self.flux.get_carray("energy")

        cdef int i, j, k, n
        cdef double a

        cdef DoubleArray arr
        cdef np.float64_t *x[3], *wx[3], *mv[3], *fmv[3]
        cdef str field, axis

        cdef int num_faces = self.mesh.faces.get_number_of_items()
        cdef int npart = self.pc.get_number_of_items()


        # compute particle and face velocities
        self._compute_face_velocities()

        # resize face/states arrays
        self.left_state.resize(num_faces)
        self.right_state.resize(num_faces)
        self.flux.resize(num_faces)

        # reconstruct left\right states at each face
        self.riemann.reconstruction.compute(self.pc, self.mesh.faces, self.left_state, self.right_state,
                self.mesh, self.gamma, dt)

        # extrapolate state to face, apply frame transformations, solve riemann solver, and transform back
        self.riemann.solve(self.flux, self.left_state, self.right_state, self.mesh.faces,
                t, dt, iteration_count, self.mesh.dim)

        self.pc.pointer_groups(mv, self.pc.named_groups['momentum'])
        self.flux.pointer_groups(fmv, self.flux.named_groups['momentum'])

        # update conserved quantities
        for n in range(num_faces):

            # update only real particles in the domain
            i = pair_i.data[n]
            j = pair_j.data[n]
            a = area.data[n]

            # flux entering cell defined by particle i
            if tags.data[i] == Real:
                m.data[i] -= dt*a*fm.data[n]
                e.data[i] -= dt*a*fe.data[n]

                for k in range(self.dim):
                    mv[k][i] -= dt*a*fmv[k][n]

            # flux leaving cell defined by particle j
            if tags.data[j] == Real:
                m.data[j] += dt*a*fm.data[n]
                e.data[j] += dt*a*fe.data[n]

                for k in range(self.dim):
                    mv[k][j] += dt*a*fmv[k][n]

        self.pc.pointer_groups(x, self.pc.named_groups['position'])
        self.pc.pointer_groups(wx, self.pc.named_groups['w'])

        # move particles
        for i in range(npart):
            if tags.data[i] == Real:
                for k in range(self.dim):
                    x[k][i] += dt*wx[k][i]


    cdef double _compute_time_step(self):

        cdef IntArray tags = self.pc.get_carray("tag")
        cdef DoubleArray r = self.pc.get_carray("density")
        cdef DoubleArray p = self.pc.get_carray("pressure")
        cdef DoubleArray vol = self.pc.get_carray("volume")

        cdef double gamma = self.gamma
        cdef double c, R, dt, vi
        cdef int i, k, npart
        cdef np.float64_t* v[3]

        self.pc.pointer_groups(v, self.pc.named_groups['velocity'])

        c = sqrt(gamma*p.data[0]/r.data[0])
        if self.dim == 2:
            R = sqrt(vol.data[0]/np.pi)
        elif self.dim == 3:
            R = pow(3.0*vol.data[0]/(4.0*np.pi), 1.0/3.0)

        vi = 0.0
        for k in range(self.dim):
            vi += v[k][0]*v[k][0]
        dt = R/(c + sqrt(vi))

        for i in range(self.pc.get_number_of_items()):
            if tags.data[i] == Real:

                c = sqrt(gamma*p.data[i]/r.data[i])

                # calculate approx radius of each voronoi cell
                if self.dim == 2:
                    R = sqrt(vol.data[i]/np.pi)
                elif self.dim == 3:
                    R = pow(3.0*vol.data[i]/(4.0*np.pi), 1.0/3.0)

                vi = 0.0
                for k in range(self.dim):
                    vi += v[k][i]*v[k][i]
                dt = fmin(R/(c + sqrt(vi)), dt)

        return dt

    cdef _compute_face_velocities(self):
        self._assign_particle_velocities()
        self._assign_face_velocities()

    cdef _assign_particle_velocities(self):
        """
        Assigns particle velocities. Particle velocities are
        equal to local fluid velocity plus a regularization
        term. The algorithm is taken from Springel (2009).
        """
        # particle flag information
        cdef IntArray tags = self.pc.get_carray("tag")

        # particle values
        cdef DoubleArray r = self.pc.get_carray("density")
        cdef DoubleArray p = self.pc.get_carray("pressure")
        cdef DoubleArray vol = self.pc.get_carray("volume")

        # local variables
        cdef np.float64_t *x[3], *v[3], *wx[3], *dcx[3]
        cdef double cs, d, R
        cdef double eta = self.eta
        cdef int i, k

        self.pc.pointer_groups(x, self.pc.named_groups['position'])
        self.pc.pointer_groups(v, self.pc.named_groups['velocity'])
        self.pc.pointer_groups(wx, self.pc.named_groups['w'])
        self.pc.pointer_groups(dcx, self.pc.named_groups['dcom'])

        for i in range(self.pc.get_number_of_items()):

            for k in range(self.dim):
                wx[k][i] = v[k][i]

            if self.regularize == 1:

                # sound speed 
                cs = sqrt(self.gamma*p.data[i]/r.data[i])

                # distance form cell com to particle position
                d = 0.0
                for k in range(self.dim):
                    d += dcx[k][i]**2
                d = sqrt(d)

                # approximate length of cell
                if self.dim == 2:
                    R = sqrt(vol.data[i]/np.pi)
                if self.dim == 3:
                    R = pow(3.0*vol.data[i]/(4.0*np.pi), 1.0/3.0)

                # regularize - eq. 63
                if ((0.9 <= d/(eta*R)) and (d/(eta*R) < 1.1)):
                    for k in range(self.dim):
                        wx[k][i] += cs*dcx[k][i]*(d - 0.9*eta*R)/(d*0.2*eta*R)

                elif (1.1 <= d/(eta*R)):
                    for k in range(self.dim):
                        wx[k][i] += cs*dcx[k][i]/d


    cdef _assign_face_velocities(self):
        """
        Assigns velocities to the center of mass of the face
        defined by neighboring particles. The face velocity
        is the average of particle velocities that define
        the face plus a residual motion. The algorithm is
        taken from Springel (2009).
        """

        # face information
        cdef LongArray pair_i = self.mesh.faces.get_carray("pair-i")
        cdef LongArray pair_j = self.mesh.faces.get_carray("pair-j")

        # local variables
        cdef double factor
        cdef int i, j, k, n
        cdef np.float64_t *x[3], *wx[3], *fv[3], *fij[3]

        self.pc.pointer_groups(x,  self.pc.named_groups['position'])
        self.pc.pointer_groups(wx, self.pc.named_groups['w'])

        self.mesh.faces.pointer_groups(fv,  self.mesh.faces.named_groups['velocity'])
        self.mesh.faces.pointer_groups(fij, self.mesh.faces.named_groups['com'])

        for n in range(self.mesh.faces.get_number_of_items()):

            # particles that define face
            i = pair_i.data[n]
            j = pair_j.data[n]

            # correct face velocity due to residual motion - eq. 32
            factor = denom = 0.0
            for k in range(self.dim):
                factor += (wx[k][i] - wx[k][j])*(fij[k][n] - 0.5*(x[k][i] + x[k][j]))
                denom  += pow(x[k][j] - x[k][i], 2.0)
            factor /= denom

            # the face velocity mean of particle velocities and residual term - eq. 33
            for k in range(self.dim):
                fv[k][n] = 0.5*(wx[k][i] + wx[k][j]) + factor*(x[k][j] - x[k][i])
