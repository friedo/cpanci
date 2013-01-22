package CPANci::Receiver { 
    use Dancer;

    any qr{.+} => sub {
        return "Hello, world"
    };


}

1;
