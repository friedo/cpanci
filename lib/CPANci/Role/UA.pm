package CPANci::Role::UA { 
    
    use Moose::Role;
    use CPANci;
    use LWP::UserAgent;

    has ua        => ( required => 0, init_arg => undef, lazy_build => 1, is => 'ro' );

    sub _build_ua { 
        my $self = shift;
        
        return LWP::UserAgent->new( agent => 'CPANci/' . $CPANci::VERSION );
    }

}

1;
