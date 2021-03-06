package CPANci::Fetcher {

    use Moose;
    use CPANci;
    use CPANci::Installer;
    use LWP::UserAgent;
    use MongoDB;
    use XML::LibXML;
    use URI;
    use JSON::XS;
    use Data::Dumper;
    use POSIX;

    use feature ':5.18';
    no warnings 'experimental';

    with 'CPANci::Role::UA';
    with 'CPANci::Role::MongoDB';

    has rss_base  => ( required => 1, isa => 'Str', is => 'ro' );
    has api_base  => ( required => 1, isa => 'Str', is => 'ro' );

    sub run {
        my $self = shift;

        $self->_check_pidfile;

        my $xml = XML::LibXML->load_xml( string => $self->ua->get( $self->rss_base )->decoded_content );
        my @dists = map {
            my $u = URI->new( $_->getAttribute( 'rdf:resource' ) );
            $u->host( 'api.metacpan.org' );
            $u->path( 'v0' . $u->path );
            $u;
        } $xml->findnodes( '//rdf:li' );

        my $count = 0;
        foreach my $dist( @dists ) {
            my ( $name ) = $dist =~ m{release/.+/(.+)$};
            my $coll = $self->mongo->get_collection( 'dists' );
            my $data = $coll->find_one( { _id => 'cpan/' . $name } );

            next if $data;

            my $ts = strftime "[%Y-%m-%d] %H:%M:%S ", localtime;
            print $ts, "fetching metadata: $dist\n";
            my $fetched_data = decode_json $self->ua->get( $dist )->decoded_content;

            my %ins = %$fetched_data;
            $ins{_id} = 'cpan/' . $name;
            $ins{CPANci} = { fetched => DateTime->now };

            $coll->insert( \%ins );

            # last if ++$count == 10;     # testing only
        }
    }

    sub _start_installer {
        my ( $self, $name, $url ) = @_;

        # fork and return;
        eval {
            CPANci::Installer->new( mongo_cfg => $self->mongo_cfg )
                ->start( name => $name, url => $url );
        };

        say $@ if $@;
    }

    sub _check_pidfile {
        my $self = shift;

        my $pidfile = "/cpanci/fetcher.pid";
        if ( -f $pidfile ) {
            my $pid = do {
                open my $fh, '<', $pidfile;
                local $/;
                readline $fh;
            };

            die "process $pid already running" if kill 0, $pid;
        }

        if ( open my $pidfh, '>', $pidfile ) {
	    print { $pidfh } $$;
	} else {
	    warn "Can't write my pid to $pidfile. Continuing anyway"
	}
    }

}

1;
