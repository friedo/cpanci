package CPANci::Fetcher {

    use Moose;
    use CPANci;
    use LWP::UserAgent;
    use MongoDB;
    use XML::LibXML;
    use URI;
    use JSON::XS;
    use Data::Dumper;
    use POSIX;

    with 'CPANci::Role::UA';
    with 'CPANci::Role::MongoDB';    

    has rss_base  => ( required => 1, isa => 'Str', is => 'ro' );
    has api_base  => ( required => 1, isa => 'Str', is => 'ro' );

    sub run {
        my $self = shift;
        
        my $xml = XML::LibXML->load_xml( string => $self->ua->get( $self->rss_base )->decoded_content );
        my @dists = map { 
            my $u = URI->new( $_->getAttribute( 'rdf:resource' ) );
            $u->host( 'api.metacpan.org' );
            $u->path( 'v0' . $u->path );
            $u;
        } $xml->findnodes( '//rdf:li' );
        
        foreach my $dist( @dists ) { 
            my ( $name ) = $dist =~ m{release/.+/(.+)$};
            my $coll = $self->mongo->get_database( 'cpanci' )->get_collection( 'dists' );
            my $data = $coll->find_one( { _id => 'cpan/' . $name } );
            
            next if $data;
            
            my $ts = strftime "[%Y-%m-%d] %H:%M:%S ", localtime;
            print $ts, "fetching metadata: $dist\n";
            my $fetched_data = decode_json $self->ua->get( $dist )->decoded_content;
            $fetched_data->{_id} = 'cpan/' . $name;
            $coll->insert( $fetched_data );
        }
    } 
}

1;
