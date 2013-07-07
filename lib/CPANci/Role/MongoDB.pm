package CPANci::Role::MongoDB { 
    use Moose::Role;
    use MongoDB;

    with 'CPANci::Role::Conf';

    has mongo     => ( required => 0, init_arg => undef, lazy_build => 1, is => 'ro' );
    
    sub _build_mongo { 
        my $self = shift;
        my $cfg = $self->conf->{mongodb};
        
        return MongoDB::MongoClient->new( %$cfg )->get_database( 'cpanci' );
    }

}


1;
