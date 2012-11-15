package CPANci::Fetcher;

use Moose;
use CPANci;
use LWP::UserAgent;
use MongoDB;
use XML::LibXML;
use URI;
use JSON::XS;
use Data::Dumper;

has rss_base  => ( required => 1, isa => 'Str', is => 'ro' );
has api_base  => ( required => 1, isa => 'Str', is => 'ro' );
has ua        => ( required => 0, init_arg => undef, lazy_build => 1, is => 'ro' );
has mongo     => ( required => 0, init_arg => undef, lazy_build => 1, is => 'ro' );
has mongo_cfg => ( required => 1, isa => 'HashRef', is => 'ro' );


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

        print "fetching metadata: $dist\n";
        my $fetched_data = decode_json $self->ua->get( $dist )->decoded_content;
        $fetched_data->{_id} = 'cpan/' . $name;
        $coll->insert( $fetched_data );
    }
}

sub _build_mongo { 
    my $self = shift;
    my $cfg = $self->mongo_cfg;

    return MongoDB::Connection->new( %$cfg );
}

sub _build_ua { 
    my $self = shift;

    return LWP::UserAgent->new( agent => 'CPANci/' . $CPANci::VERSION );
}


1;
