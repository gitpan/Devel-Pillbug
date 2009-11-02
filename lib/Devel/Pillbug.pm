package Devel::Pillbug::MasonHandler;

use base qw| HTML::Mason::CGIHandler |;

#
# Parent does funny things with eval before we can.
#
# Delegate to H::M::R instead.
#
sub exec {
  my $self = shift;

  return HTML::Mason::Request::exec( $self, @_ );
}

package Devel::Pillbug;

our $VERSION = 0.004;

use strict;
use warnings;

use base qw/HTTP::Server::Simple::Mason/;

use File::HomeDir;
use File::Type;

sub docroot {
  my $self = shift;
  my $docroot = shift;

  $self->{_docroot} = $docroot if $docroot;

  return $self->{_docroot} if $self->{_docroot};

  my $home = File::HomeDir->my_home;

  my $pubHtml = join( "/", $home, "public_html" );
  my $sites   = join( "/", $home, "Sites" );

  $self->{_docroot} = ( -d $sites ) ? $sites : $pubHtml;

  return $self->{_docroot};
}

sub mason_config {
  my $self = shift;

  return ( comp_root => $self->docroot() );
}

sub net_server {
  return "Net::Server::PreFork";
}

#
#
#
sub _handle_mason_request {
  my $self = shift;
  my $cgi  = shift;
  my $path = shift;

  my $r = HTML::Mason::FakeApache->new( cgi => $cgi );

  my $m = $self->mason_handler;

  my $comp = $m->interp->make_component( comp_file => $path );

  my $buffer;

  my $req = $m->interp->make_request(
    comp        => $comp,
    args        => [ $cgi->Vars ],
    cgi_request => $r,
    out_method  => \$buffer,
  );

  $r->{http_header_sent} = 1;

  $m->interp->set_global( '$r', $r );

  HTML::Mason::Request::exec($req);

  #
  #
  #
  if ( $@ && ( !$r->status || ( $r->status !~ /^302/ ) ) ) {
    $r->status("500 Internal Server Error");
  } elsif ( !$r->status ) {
    $r->status("200 OK");
  }

  #
  #
  #
  my $header = $r->http_header;
  $header =~ s|^Status:|HTTP/1.0|;

  print $header;

  print $buffer if $buffer;
}

sub handler_class {
  return "Devel::Pillbug::MasonHandler";
}

#
# Sombunall of this is from H::S::S::Mason
#
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
  my $path = join( "", $conf{comp_root}, $cgi->path_info );

  if ( !-e $path ) {
    print "HTTP/1.0 404 Not Found\r\n";
    print "Content-Type: text/html\r\n";
    print "\r\n";
    print "<h1>Not Found</h1>\r\n";

  } elsif ( $path =~ /html$/ ) {
    return $self->_handle_mason_request( $cgi, $path );

  } else {
    my $ft   = File::Type->new();
    my $type = $ft->mime_type($path);

    print "HTTP/1.0 200 OK\r\n";
    print "Content-Type: $type\r\n";
    print "\r\n";
    open( IN, "<", $path );
    while (<IN>) {
      print $_;
    }
    close(IN);
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

All arguments are optional:

  > pillbug -host example.com -port 8080 -docroot /tmp/foo

Do it in Perl:

  use Devel::Pillbug;

  my $port = 8000; # Optional argument, default is 8080

  my $server = Devel::Pillbug->new($port);

  #
  # Optional: Use methods from HTTP::Server::Simple
  #
  # $server->host("example.com");

  #
  # Optional: Override the document root
  #
  # $server->docroot("/tmp/foo");

  $server->run;

=head1 DESCRIPTION

Devel::Pillbug is a simple HTML::Mason server for dev environments.

It is designed for zero configuration and easy install from CPAN.

Devel::Pillbug uses the "public_html" or "Sites" directory of the
user who launched the process for its document root. Files ending
in "html" are treated as Mason components.

=head1 METHODS

See L<HTTP::Server::Simple> and L<HTTP::Server::Simple::Mason> for
inherited methods.

=over 4

=item * $self->docroot($docroot);

Returns the currently active docroot.

The server will set its docroot to the received path, if one is
supplied as an argument.

=back

=head1 CONFIGURATION AND ENVIRONMENT

The document root must exist and be readable, and Devel::Pillbug
must be able to bind to its listen port (default 8080).

=head1 VERSION

This document is for version .004 of Devel::Pillbug.

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
