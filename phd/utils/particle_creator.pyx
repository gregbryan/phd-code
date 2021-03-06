from .particle_tags import ParticleTAGS
from ..containers.containers cimport CarrayContainer

def HydroParticleCreator(num=0, dim=2, parallel=False):

    cdef dict named_groups = {}
    cdef str axis, dimension = 'xyz'[:dim]
    cdef CarrayContainer pc = CarrayContainer(num)

    # register primitive fields
    named_groups['position'] = []
    named_groups['velocity'] = []
    pc.register_property(num, 'density', 'double')

    for axis in dimension:

        pc.register_property(num, 'position-' + axis, 'double')
        pc.register_property(num, 'velocity-' + axis, 'double')

        named_groups['position'].append('position-' + axis)
        named_groups['velocity'].append('velocity-' + axis)

    pc.register_property(num, 'pressure', 'double')

    # register conservative fields
    named_groups['momentum'] = []
    pc.register_property(num, 'mass', 'double')

    for axis in dimension:

        pc.register_property(num, 'momentum-' + axis, 'double')
        named_groups['momentum'].append('momentum-' + axis)

    pc.register_property(num, 'energy', 'double')

    # information for prallel runs
    if parallel:

        pc.register_property(num, 'key', 'longlong')
        pc.register_property(num, 'process', 'long')

    # ghost labels 
    pc.register_property(num, 'tag', 'int')
    pc.register_property(num, 'type', 'int')

    # ** remove and place in boundary **
    pc.register_property(num, 'ids', 'long')
    pc.register_property(num, 'map', 'long')

    # particle geometry
    named_groups['w'] = []
    named_groups['dcom'] = []
    pc.register_property(num, 'volume', 'double')
    pc.register_property(num, 'radius', 'double')

    for axis in dimension:

        pc.register_property(num, 'w-' + axis, 'double')
        pc.register_property(num, 'dcom-' + axis, 'double')

        named_groups['w'].append('w-' + axis)
        named_groups['dcom'].append('dcom-' + axis)

    named_groups['primitive'] = ['density'] +\
            named_groups['velocity'] +\
            ['pressure']
    named_groups['conserative'] = ['mass'] +\
            named_groups['momentum'] +\
            ['energy']

    # set initial particle tags to be real
    pc['tag'][:] = ParticleTAGS.Real
    pc.named_groups = named_groups

    return pc

#def MhdParticleCreator(num=0, dim=2, parallel=False):
#    pass
