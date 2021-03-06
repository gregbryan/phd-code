from riemann_base import RiemannBase
import numpy as np
import riemann

class Hll2D(RiemannBase):
    """
    2d hll riemann solver
    """
    def __init__(self, reconstruction=None):
        self.dim = 2
        self.reconstruction = reconstruction


    def get_dt(self, fields, vol, gamma):
        """
        calculate the global timestep for the simulation
        """
        # grab values that correspond to real particles
        dens = fields.get_field("density")
        velx = fields.get_field("velocity-x")
        vely = fields.get_field("velocity-y")
        pres = fields.get_field("pressure")

        # sound speed
        c = np.sqrt(gamma*pres/dens)

        # calculate approx radius of each voronoi cell
        R = np.sqrt(vol/np.pi)

        dt_x = R/(abs(velx) + c)
        dt_y = R/(abs(vely) + c)

        return min(dt_x.min(), dt_y.min())


    def reconstruct_face_states(self, particles, particles_index, graphs, primitive, cells_info, faces_info, gamma, dt):
        """
        reconstruct primitive particle values to face values
        """
        # construct left and right states and each face
        self.left_right_states(primitive, faces_info)

        # calculate gradients for each primitive variable
        self.reconstruction.gradient(primitive, particles, particles_index, cells_info, graphs)

        # reconstruct states at faces - hack for right now
        ghost_map = particles_index["ghost_map"]
        cell_com = np.hstack((cells_info["center of mass"], cells_info["center of mass"][:, np.asarray([ghost_map[i] for i in particles_index["ghost"]])]))
        self.reconstruction.extrapolate(faces_info, cell_com, gamma, dt)


    def solver(self, left_face, right_face, fluxes, normal, faces_info, gamma, num_faces):
        """
        solve the riemann problem using the 2d hll solver
        """
        riemann.hll_2d(left_face, right_face, fluxes, normal, faces_info["velocities"], gamma, num_faces)
