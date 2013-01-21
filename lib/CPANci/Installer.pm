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
    use TAP::Parser;
    use Data::Dumper;
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

            $self->rdata->{tests} = $self->_run_tests( $perl );
            print JSON::XS->new->pretty->encode( $self->rdata->{tests} );

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
            
        my $results = $self->_read_cpanm_deps_log( $err );

    }

    # implements a kinda sloppy pseudo-state machine for parsing the cpanm log
    sub _read_cpanm_deps_log { 
        my ( $self, $fh ) = @_;

        my %deps;
        my @working_on;    # <--- stack
        my @log_lines;

        while ( my $line = readline $fh ) { 
            my $log_line = { indent => scalar @working_on, line => $line };
            push @log_lines, $log_line;

            given ( $line ) { 
                when ( m{==> Found dependencies: (?<deps>.+)$} ) { 
                    my @dep_names = split /, /, $+{deps};
                    $deps{$_} = { } for @dep_names;
                    $log_line->{type} = 'found-deps';
                }
                when ( m{--> Working on (?<woname>.+)$} ) { 
                    push @working_on, $+{woname};
                    $log_line->{type} = 'working-on';
                }
                when ( m{(?<stage>Fetching|Configuring|Building)} ) { 
                    my $key = { Fetching => 'fetch', Configuring => 'config', Building => 'build' }->{ $+{stage} };

                    $log_line->{type} = $key;

                    if ( /OK$/ ) { 
                        $deps{$working_on[-1]}{$key} = 1;
                        break;
                    }

                    $deps{$working_on[-1]}{$key} = 0;
                    pop @working_on;
                }
                when ( m{Successfully installed (?<dist>.+)$} ) { 
                    $log_line->{type} = 'success';
                    $deps{$working_on[-1]}{install} = 1;
                    $deps{$working_on[-1]}{install_dist} = $+{dist};
                    pop @working_on;
                }
                default { 
                    $log_line->{type} = 'misc';
                }
            }
        }

        return { deps => \%deps, log => \@log_lines };
    }    
    
    sub _run_tests { 
        my $self = shift;
        my $perl = shift;

        my $plbin = catfile $self->pldir, $perl, 'bin', 'perl';
        system $plbin, $self->cpanm, '--notest', '.';
        my @tests = $self->_get_tests( glob "t/*" );

        my @results;

        foreach my $test( @tests ) { 
            my @test_results;
            my $parser = TAP::Parser->new( { source => $test } );
            while( my $result = $parser->next ) { 
                push @test_results, 
                  { text => $result->as_string,
                    ok   => ( $result->is_ok ? \1 : \0 ),
                    type => $result->type,
                    $result->type eq 'test' ?
                    ( number => $result->number,
                      desc   => ( $result->description =~ s/^- //r ),
                    ) : ( ),
                    
                  }
            }

            push @results, { name => $test, lines => \@test_results };
        }

        return \@results;
    }

    sub _get_tests { 
        my $self = shift;
        my @glob = @_;

        my @tests;

        # for now we will just naively get anything that ends in .t.
        foreach my $thing( @glob ) { 
            if ( -f $thing && $thing =~ /\.t$/ ) { 
                push @tests, $thing;
            } elsif ( -d $thing ) { 
                push @tests, $self->_get_tests( glob "$thing/*" );
            }
        }

        return @tests;
    }

    sub _build_perls { 
        return 
          [ 'narf-5.16.2' ];
    }


}


1;
                
