import phd
import numpy as np
from mpi4py import MPI

#example to run:
#$ mpirun -n 5 python sedov_2d_cartesian.py

comm = MPI.COMM_WORLD
rank = comm.Get_rank()
size = comm.Get_size()

if rank == 0:

    gamma = 1.4

    Lx = 1.    # domain size in x
    nx = 128   # particles per dim
    n = nx*nx  # number of points

    rho_1 = 1.0; rho_2 = 2.0
    vel = 0.5; amp = 0.05

    dx = Lx/nx # spacing between particles

    # create particle container
    pc_root = phd.ParticleContainer(n)
    part = 0
    for i in range(nx):
        for j in range(nx):

            x = (i+0.5)*dx
            y = (j+0.5)*dx

            pert = amp*np.sin(4.*np.pi*x)

            if 0.25 < y and y < 0.75:

                pc_root['density'][part] = rho_1
                pc_root['velocity-x'][part] = -(vel + pert)

            else:

                pc_root['density'][part] = rho_2
                pc_root['velocity-x'][part] = vel + pert


            pc_root['position-x'][part] = x
            pc_root['position-y'][part] = y
            pc_root['velocity-y'][part] = pert
            pc_root['ids'][part] = part
            part += 1

    pc_root['pressure'][:] = 2.5
    pc_root['velocity-y'][:] = 0.0

    # how many particles to each process
    nsect, extra = divmod(n, size)
    lengths = extra*[nsect+1] + (size-extra)*[nsect]
    send = np.array(lengths)

    # how many particles 
    disp = np.zeros(size, dtype=np.int32)
    for i in range(1,size):
        disp[i] = send[i-1] + disp[i-1]

else:

    lengths = disp = send = None
    pc_root = {
            'position-x': None,
            'position-y': None,
            'density': None,
            'pressure': None,
            'ids': None
            }

# tell each processor how many particles it will hold
send = comm.scatter(send, root=0)

# allocate local particle container
pc = phd.ParticleContainer(send)

# import particles from root
fields = ['position-x', 'position-y', 'density', 'pressure', 'ids']
for field in fields:
    comm.Scatterv([pc_root[field], (lengths, disp)], pc[field])

pc['process'][:] = rank
pc['tag'][:] = phd.ParticleTAGS.Real
pc['type'][:] = phd.ParticleTAGS.Undefined

domain = phd.DomainLimits(dim=2, xmin=0., xmax=1.)           # spatial size of problem 
load_bal = phd.LoadBalance(domain, comm, order=21)           # tree load balance scheme
boundary = phd.BoundaryParallel(domain,                      # periodic boundary condition
        boundary_type=phd.BoundaryType.Periodic,
        load_bal, comm)
mesh = phd.Mesh(boundary)                                    # tesselation algorithm
reconstruction = phd.PieceWiseConstant()                     # constant reconstruction
riemann = phd.HLLC(reconstruction, gamma=1.4, cfl=0.5)       # riemann solver
integrator = phd.MovingMesh(pc, mesh, riemann, regularize=1) # integrator 
solver = phd.SolverParallel(integrator,                      # simulation driver
        cfl=0.5, tf=2.5, pfreq=25,
        relax_num_iterations=0,
        output_relax=False,
        fname='kh_2d_cartesian')
solver.solve()
