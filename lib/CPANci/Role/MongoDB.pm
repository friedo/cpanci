package CPANci::Role::MongoDB { 
    use Moose::Role;
    use MongoDB;

    has mongo     => ( required => 0, init_arg => undef, lazy_build => 1, is => 'ro' );
    has mongo_cfg => ( required => 1, isa => 'HashRef', is => 'ro' );
    
    sub _build_mongo { 
        my $self = shift;
        my $cfg = $self->mongo_cfg;
        
        return MongoDB::MongoClient->new( %$cfg );
    }

}


1;
