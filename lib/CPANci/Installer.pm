package CPANci::Installer { 
    use Moose;
    use CPANci;
    use Cwd;
    use Parallel::ForkManager;
    use JSON::XS;
    use IPC::Open3;
    use Symbol 'gensym';
    use File::Temp 'tempfile', 'tempdir';
    use File::Spec::Functions 'catdir', 'catfile';
    use TAP::Parser;
    use Data::Dumper;
    use autodie;
    use boolean;

    use strict;
    use warnings;
    use feature ':5.18';
    no warnings 'experimental';
    

    with 'CPANci::Role::UA';
    with 'CPANci::Role::MongoDB';

    has perls   => ( required => 1, is => 'ro', isa => 'ArrayRef', lazy_build => 1 );
    has home    => ( required => 1, is => 'ro', isa => 'Str', default => '/cpanci' );
    has master  => ( required => 1, is => 'ro', isa => 'Str', default => '/cpanci/perl5/perlbrew/perls/master/bin/perl' );
    has cpanm   => ( required => 1, is => 'ro', isa => 'Str', default => '/cpanci/perl5/perlbrew/perls/master/bin/cpanm');
    has pldir   => ( required => 1, is => 'ro', isa => 'Str', default => '/cpanci/perl5/perlbrew/perls' );
    has distdir => ( required => 1, is => 'ro', isa => 'Str', default => '/cpanci/dist' );
    has rdata   => ( required => 1, is => 'ro', isa => 'HashRef', default => sub { { } } );

    sub start { 
        my ( $self, %args ) = @_;

        die "no download url" unless $args{url};
        die "no dist name"    unless $args{name};

        my ( $tfh, $tfname ) = tempfile;

        say "getting $args{url} -> $tfname";
        $self->ua->get( $args{url}, ":content_file" => $tfname );

        my $cwd = getcwd;
        foreach my $perl ( @{ $self->perls } ) { 
            my $workdir = catdir $self->home, 'work', $perl; 
            next unless -d $workdir;
            chdir $workdir;

            say "extracting to $workdir";
            system 'tar', '-xzvf', $tfname;
           
            my $dist_tmp = tempdir( DIR => $self->distdir, cleanup => 1 );

            chdir catdir $workdir, $args{name};
            $self->rdata->{deps}  = eval { $self->_install_deps( $perl, $dist_tmp ) };
            $self->rdata->{deps}{error} =  $@ if $@;

            $self->rdata->{tests} = eval { $self->_run_tests( $perl, $dist_tmp ) };
            $self->rdata->{tests}{error} = $@ if $@;

            eval { $self->_save_results( $perl, $args{name} ) };
            say "save error: $@" if $@;

            chdir $cwd;
        }
    }

    sub _save_results { 
        my ( $self, $perl, $dist ) = @_;
        
        my $db = $self->mongo->get_database( 'cpanci' );

        $db->get_collection( 'deps'  )->insert( { 
            dist  => "cpan/$dist", 
            perl  => $perl, 
            deps  => $self->rdata->{deps}
        } );

        $db->get_collection( 'tests' )->insert( { 
            dist  => "cpan/$dist", 
            perl  => $perl,
            tests => $self->rdata->{tests}
         } );
    }

    sub _install_deps { 
        my ( $self, $perl, $dist_tmp ) = @_;

        my $plbin = catfile $self->pldir, $perl, 'bin', 'perl';
        my( $wtr, $rdr );
        my $err = gensym;
        my $pid = open3 $wtr, $rdr, $err, $plbin, $self->cpanm, '--installdeps', '--notest', '-L', $dist_tmp, '.';
    
        my $results = $self->_read_cpanm_deps_log( $err );

        waitpid $pid, 0;

        return $results;
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
                    push @working_on, $+{woname} eq '.' ? 'THIS' : $+{woname};
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
        my ( $self, $perl, $dist_tmp ) = @_;

        my $plbin = catfile $self->pldir, $perl, 'bin', 'perl';
        system $plbin, $self->cpanm, '--notest', '-L', $dist_tmp, '.';
        my @tests = $self->_get_tests( glob "t/*" );

        my @results;

        foreach my $test( @tests ) { 
            my @test_results;

            my ( $wtr, $rdr );
            my $err = gensym;

            my $perlbin = catfile $self->pldir, $perl, 'bin', 'perl';
            
            my $idir = catdir $dist_tmp, 'lib', 'perl5';
            my $pid = open3 $wtr, $rdr, $err, $perlbin, '-I', $idir, $test;

            my ( $tap_out, $errors );

            {
                local $/;
                $tap_out = readline $rdr;
                $errors  = readline $err;
            }

            waitpid $pid, 0;
            my $passed = ( ( $? >> 8 ) == 0 ? true : false );

            eval { 
                my $parser = TAP::Parser->new( { source => $tap_out } );
                while( my $result = $parser->next ) { 
                    push @test_results, 
                      { text => $result->as_string,
                        ok   => ( $result->is_ok ? true : false ),
                        type => $result->type,
                        $result->type eq 'test' ?
                        ( number => $result->number,
                          desc   => ( $result->description =~ s/^- //r ),
                        ) : ( ),    
                      }
                }
            };

            push @results, { name => $test, 
                             $@ ? ( error => $@ ) : ( ),
                             lines => \@test_results, 
                             raw_err => $errors,
                             raw_tap => $tap_out,
                             passed => $passed };
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
        my $self = shift;

        return [ map { $_->{version} } $self->mongo->get_database( 'cpanci' )->get_collection( 'perls' )->find->all ];
    }


}


1;
                
