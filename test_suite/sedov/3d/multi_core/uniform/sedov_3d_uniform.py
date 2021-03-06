import phd
import numpy as np
from mpi4py import MPI

#to run:
#$ mpirun -n 4 python sedov_2d_cartesian.py

comm = MPI.COMM_WORLD
rank = comm.Get_rank()
size = comm.Get_size()

if rank == 0:

    gamma = 1.4

    Lx = 1.       # domain size in x
    nx = 50       # particles per dim
    n = nx*nx*nx  # number of particles

    # create particle container
    pc_root = phd.ParticleContainer(n, dim=3)

    part = 0
    np.random.seed(0)
    for i in range(nx):
        for j in range(nx):
            for k in range(nx):
                pc_root['position-x'][part] = np.random.rand()
                pc_root['position-y'][part] = np.random.rand()
                pc_root['position-z'][part] = np.random.rand()
                pc_root['ids'][part] = part
                part += 1

    # set ambient values
    pc_root['density'][:]  = 1.0               # density
    pc_root['pressure'][:] = 1.0E-5*(gamma-1)  # total energy

    # put all enegery in center particle
    r = 0.1
    cells = ( (pc_root['position-x']-.5)**2 \
            + (pc_root['position-y']-.5)**2 \
            + (pc_root['position-z']-.5)**2 ) <= r**2
    pc_root['pressure'][cells] = 1.0/(4.0*np.pi*r**3/3.)*(gamma-1)

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
            'position-z': None,
            'density': None,
            'pressure': None,
            'ids': None
            }

# tell each processor how many particles it will hold
send = comm.scatter(send, root=0)

# allocate local particle container
pc = phd.ParticleContainer(send, dim=3)

# import particles from root
fields = ['position-x', 'position-y', 'position-z', 'density', 'pressure', 'ids']
for field in fields:
    comm.Scatterv([pc_root[field], (lengths, disp)], pc[field])

pc['velocity-x'][:] = 0.0
pc['velocity-y'][:] = 0.0
pc['velocity-z'][:] = 0.0
pc['process'][:] = rank
pc['tag'][:] = phd.ParticleTAGS.Real
pc['type'][:] = phd.ParticleTAGS.Undefined

domain = phd.DomainLimits(dim=3, xmin=0., xmax=1.)           # spatial size of problem
load_bal = phd.LoadBalance(domain, comm, order=18)           # tree load balance scheme
boundary = phd.BoundaryParallel(domain,                      # reflective boundary condition
        phd.BoundaryType.Reflective,
        load_bal, comm)
mesh = phd.Mesh(boundary)                                    # tesselation algorithm
reconstruction = phd.PieceWiseConstant()                     # constant reconstruction
riemann = phd.HLL(reconstruction, gamma=1.4)                 # riemann solver
integrator = phd.MovingMesh(pc, mesh, riemann, regularize=1) # integrator 
solver = phd.SolverParallel(integrator, load_bal,            # simulation driver
        cfl=0.5, comm=comm, tf=0.1, pfreq=1,
        relax_num_iterations=8,
        output_relax=False,
        fname='sedov_2d_uniform')
solver.solve()
