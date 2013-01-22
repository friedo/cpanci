package CPANci::Receiver { 
    use Dancer;
    use MongoDB;

    any qr{.+} => sub {
        return "Hello, world"
    };

    dance;

}


1;
