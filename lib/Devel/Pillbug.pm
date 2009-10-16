package Devel::Pillbug;

our $VERSION = 0.001;

use strict;
use warnings;

use base qw/HTTP::Server::Simple::Mason/;

use File::HomeDir;
use File::Type;

our $root;

sub root {
  return $root if $root;

  my $home = File::HomeDir->my_home;

  my $pubHtml = join( "/", $home, "public_html" );
  my $sites   = join( "/", $home, "Sites" );

  $root = ( -d $sites ) ? $sites : $pubHtml;

  return $root;
}

sub mason_config {
  my $home = File::HomeDir->my_home;

  return ( comp_root => root() );
}

sub net_server {
  return "Net::Server::PreFork";
}

sub handle_request {
  my $self = shift;
  my $cgi  = shift;

  my $m = $self->mason_handler;
  unless ( $m->interp->comp_exists( $cgi->path_info ) ) {
    my $path = $cgi->path_info;
    $path .= '/' unless $path =~ m{/$};
    $path .= 'index.html';
    $cgi->path_info($path)
      if $m->interp->comp_exists($path);
  }

  local $@;

  my %conf = $self->mason_config;
  my $path = join("", $conf{comp_root}, $cgi->path_info);

  if ( $path =~ /html$/ ) {
    my $status = eval { $m->handle_cgi_object($cgi) };
    if ( my $error = $@ ) {
      $self->handle_error($error);
    }
  } elsif ( -e $path ) {
    my $ft = File::Type->new();
    my $type = $ft->mime_type($path);

    print STDOUT "HTTP/1.0 200 OK\r\n";
    print STDOUT "Content-Type: $type\r\n";
    print STDOUT "\r\n";
    open(IN, "<", $path);
    while(<IN>){
      print STDOUT $_;
    }
    close(IN);
  } else {
    print STDOUT "HTTP/1.0 404 Not Found\r\n";
    print STDOUT "Content-Type: text/html\r\n";
    print STDOUT "\r\n";
    print STDOUT "<h1>Not Found</h1>\r\n";
  }
}

1;
__END__

=pod

=head1 NAME

Devel::Pillbug - Instant HTML::Mason server for dev environments

=head1 SYNOPSIS

Install Devel::Pillbug:

  > perl -MCPAN -e 'install Devel::Pillbug';

Start Devel::Pillbug:

  > pillbug;

Optionally specify a port:

  > pillbug 8000

Do it in Perl:

  use Devel::Pillbug;

  my $port = 8000; # Optional argument, default is 8080

  my $server = Devel::Pillbug->new($port);

  $server->run;

=head1 DESCRIPTION

Devel::Pillbug is a simple HTML::Mason server for dev environments.

It is designed for zero configuration, and easy install from CPAN.

Devel::Pillbug uses the "public_html" or "Sites" directory of the
user who launched the process for its document root. Files ending
in "html" are treated as Mason components, otherwise the raw document
is sent.

=head1 CONFIGURATION AND ENVIRONMENT

The document root must exist and be readable, and Devel::Pillbug
must be able to bind to its listen port (default 8080).

Otherwise, this space intentionally left blank.

=head1 AUTHOR

Alex Ayars <pause@nodekit.org>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2009, Alex Ayars <pause@nodekit.org>

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl 5.10.0 or later. See:
http://dev.perl.org/licenses/

=head1 SEE ALSO

L<File::HomeDir>, L<File::Type>, L<Net::Server::PreFork>.

This module extends L<HTTP::Server::Simple::Mason>.

=cut
