use v5.16;

package CPANci::Installer { 
    
    use Moose;
    use CPANci;
    use Cwd;
    use Parallel::ForkManager;
    use JSON::XS;
    use IPC::Open3;
    use Symbol 'gensym';
    use File::Temp 'tempfile';
    use File::Spec::Functions 'catdir', 'catfile';

    use autodie;

    with 'CPANci::Role::UA';

    has perls   => ( required => 1, is => 'ro', isa => 'ArrayRef', lazy_build => 1 );
    has home    => ( required => 1, is => 'ro', isa => 'Str', default => "/home/cpanci" );
    has master  => ( required => 1, is => 'ro', isa => 'Str', default => "/home/cpanci/perl5/perlbrew/perls/master/bin/perl" );
    has cpanm   => ( required => 1, is => 'ro', isa => 'Str', default => "/home/cpanci/perl5/perlbrew/perls/master/bin/cpanm" );
    has pldir   => ( required => 1, is => 'ro', isa => 'Str', default => "/home/cpanci/perl5/perlbrew/perls" );
    has rdata   => ( required => 1, is => 'ro', isa => 'HashRef', default => sub { { } } );

    sub run { 
        my ( $self, %args ) = @_;

        die "no download url" unless $args{url};
        die "no dist name"    unless $args{name};

        my ( $tfh, $tfname ) = tempfile;

        $self->ua->get( $args{url}, ":content_file" => $tfname );

        my $cwd = getcwd;
        foreach my $perl ( @{ $self->perls } ) { 
            chdir catdir $self->home, 'work', $perl;
            system 'tar', '-xzvf', $tfname;

            chdir catdir $self->home, 'work', $perl, $args{name};

            $self->rdata->{deps} = $self->_install_deps( $perl );
            print JSON::XS->new->pretty->encode( $self->rdata->{deps} );

            chdir $cwd;
        }
    }

    sub _install_deps { 
        my $self = shift;
        my $perl = shift;
        my $plbin = catfile $self->pldir, $perl, 'bin', 'perl';
        my( $wtr, $rdr );
        my $err = gensym;
        my $pid = open3 $wtr, $rdr, $err, $plbin, $self->cpanm, '--installdeps', '--notest', '.';
            
        my $results = $self->_read_cpanm_log( $err );

    }

    # implements a kinda sloppy pseudo-state machine for parsing the cpanm log
    sub _read_cpanm_log { 
        my ( $self, $fh ) = @_;

        my %deps;
        my @working_on;    # <--- stack

        while ( my $line = readline $fh ) { 
            given ( $line ) { 
                when ( m{==> Found dependencies: (?<deps>.+)$} ) { 
                    my @dep_names = split /, /, $+{deps};
                    $deps{$_} = { } for @dep_names;
                }
                when ( m{--> Working on (?<woname>.+)$} ) { 
                    push @working_on, $+{woname};
                }
                when ( m{(?<stage>Fetching|Configuring|Building)} ) { 
                    my $key = { Fetching => 'fetch', Configuring => 'config', Building => 'build' }->{ $+{stage} };
                    if ( /OK$/ ) { 
                        $deps{$working_on[-1]}{$key} = 1;
                        break;
                    }

                    $deps{$working_on[-1]}{$key} = 0;
                }
                when ( m{Successfully installed (?<dist>.+)$} ) { 
                    $deps{$working_on[-1]}{install} = 1;
                    $deps{$working_on[-1]}{install_dist} = $+{dist};
                    pop @working_on;
                }
            }
        }

        return { deps => \%deps };
    }    
    

    sub _build_perls { 
        return 
          [ 'narf-5.16.2' ];
    }


}


1;
                
