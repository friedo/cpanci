package CPANci::Role::Conf { 
    use Moose::Role;
    use File::Slurp 'slurp';
    use JSON::XS;
    use Const::Fast;

    const my $CONF => decode_json slurp "$ENV{HOME}/conf.json";
    sub conf { $CONF } 
}

1;
