package Devel::Pillbug::MasonHandler;

use strict;
use warnings;

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

our $VERSION = 0.005;

use strict;
use warnings;

use File::HomeDir;
use File::Type;

use base qw| HTTP::Server::Simple::Mason |;

use constant DefaultServerType   => "Net::Server::PreFork";
use constant DefaultHandlerClass => "Devel::Pillbug::MasonHandler";

use constant DefaultIndexName => "index";
use constant DefaultCompExt   => "html";

our $serverType   = DefaultServerType;
our $handlerClass = DefaultHandlerClass;

#
#
#
sub net_server {
  my $class         = shift;
  my $newServerType = shift;

  if ($newServerType) {
    if ( !UNIVERSAL::isa( $newServerType, "Net::Server" ) ) {
      warn "net_server() requires a Net::Server subclass";
    }

    $serverType = $newServerType;
  }

  return $serverType;
}

#
#
#
sub handler_class {
  my $class           = shift;
  my $newHandlerClass = shift;

  if ($newHandlerClass) {
    if ( !UNIVERSAL::isa( $newHandlerClass, "HTML::Mason::Request" ) ) {
      warn "handler_class() requires a HTML::Mason::Request subclass";
    }

    $handlerClass = $newHandlerClass;
  }

  return $handlerClass;
}

#
#
#
sub docroot {
  my $self    = shift;
  my $docroot = shift;

  $self->{_docroot} = $docroot if $docroot;

  if ( !$self->{_docroot} ) {
    my $home = File::HomeDir->my_home;

    my $pubHtml = join "/", $home, "public_html";
    my $sites   = join "/", $home, "Sites";

    $self->{_docroot} = ( -d $sites ) ? $sites : $pubHtml;
  }

  if ( !-d $self->{_docroot} ) {
    warn "docroot $self->{_docroot} is not a usable directory";
  }

  return $self->{_docroot};
}

#
#
#
sub allow_index {
  my $self = shift;

  $self->{_allow_index} ||= 0;

  if ( scalar(@_) ) {
    $self->{_allow_index} = $_[0] ? 1 : 0;
  }

  return $self->{_allow_index};
}

#
#
#
sub index_name {
  my $self  = shift;
  my $index = shift;

  $self->{_index} = $index if $index;

  $self->{_index} ||= DefaultIndexName;

  return $self->{_index};
}

#
#
#
sub comp_ext {
  my $self = shift;
  my $ext  = shift;

  $self->{_ext} = $ext if $ext;

  $self->{_ext} ||= DefaultCompExt;

  return $self->{_ext};
}

#
#
#
sub mason_config {
  my $self = shift;

  return ( comp_root => $self->docroot() );
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

sub _handle_directory_request {
  my $self = shift;
  my $r    = shift;

  my $fsPath   = shift;
  my $compPath = shift;

  print "HTTP/1.0 200 OK\r\n";
  print "Content-Type: text/html\r\n";
  print "\r\n";
  print "<h1>Index of $compPath</h1>\r\n";
  print "<ul>\r\n";

  my %conf = $self->mason_config;

  for ( <$fsPath/*> ) {
    my $path = $_;
    $path =~ s/^$conf{comp_root}$compPath\///;

    print "<li> <a href=\"$path\">$path</a></li>\r\n";
  }

  print "</ul>\r\n";
}

sub _handle_document_request {
  my $self = shift;
  my $r    = shift;

  my $fsPath   = shift;
  my $compPath = shift;

  my $ft   = File::Type->new();
  my $type = $ft->mime_type($fsPath);

  my @out;

  eval {
    open( IN, "<", $fsPath ) || die $!;
    while (<IN>) { push @out, $_ }
    close(IN);
  };

  if ( $@ ) {
    return $self->_handle_error($r, $@);
  }

  print "HTTP/1.0 200 OK\r\n";
  print "Content-Type: $type\r\n";
  print "\r\n";

  while (@out) { print shift @out }
}

sub _handle_notfound_request {
  my $self = shift;
  my $r    = shift;

  my $fsPath   = shift;
  my $compPath = shift;

  print "HTTP/1.0 404 Not Found\r\n";
  print "Content-Type: text/html\r\n";
  print "\r\n";
  print "<h1>Not Found</h1>\r\n";
  print "<p>The requested URL $compPath was not found on this server.\r\n";
}

sub _handle_error {
  my $self = shift;
  my $r    = shift;

  my $err = shift;

  $err =~ s/at \S+ line \d+.*//;

  print "HTTP/1.0 500 Internal Server Error\r\n";
  print "Content-type: text/html\r\n";
  print "\r\n";
  print "<h1>Internal Server Error</h1>\r\n";
  print "<p>The server could not complete your request. The error was:</p>\r\n";
  print "<p>$err</p>\r\n";
}

sub _handle_directory_redirect {
  my $self = shift;
  my $compPath = shift;

  my $url = sprintf 'http://%s:%s%s/', $self->host, $self->port, $compPath;

  print "HTTP/1.0 302 Moved\r\n";
  print "Location: $url\r\n";
  print "\r\n";
  print "<h1>Moved</h1>\r\n";
  print "<p>The document is available <a href=\"$url\">here</a>.</p>\r\n";
}

#
# Adapted from H::S::S::Mason
#
sub handle_request {
  my $self = shift;
  my $r    = shift;

  local $@;

  my %conf = $self->mason_config;
  my $m    = $self->mason_handler;

  my $compPath = $r->path_info;
  my $fsPath = join "", $conf{comp_root}, $compPath;

  my $ext = $self->comp_ext;

  my $indexFilename = join ".", $self->index_name, $ext;

  if ( -d $fsPath
    && $compPath !~ m{/$}
    && ( -e join( "/", $fsPath, $indexFilename ) || $self->allow_index ) )
  {
    return $self->_handle_directory_redirect($compPath);

  } elsif ( -d $fsPath ) {
    my $indexPath = join "/", $fsPath, $indexFilename;

    if ( -e $indexPath ) {
      $compPath .= $indexFilename;
      $fsPath   .= $indexFilename;

      $r->path_info($compPath);
    }
  }

  if ( $compPath =~ /$ext$/ && $m->interp->comp_exists($compPath) ) {
    $self->_handle_mason_request( $r, $fsPath, $compPath );

  } elsif ( $self->allow_index && -d $fsPath ) {
    $self->_handle_directory_request( $r, $fsPath, $compPath );

  } elsif ( !-d $fsPath && -e $fsPath ) {
    $self->_handle_document_request( $r, $fsPath, $compPath );

  } else {
    $self->_handle_notfound_request( $r, $fsPath, $compPath );

  }
}

1;
__END__

=pod

=head1 NAME

Devel::Pillbug - Tiny HTML::Mason server

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

Devel::Pillbug is a tiny embedded L<HTML::Mason> server, based on
L<HTTP::Server::Simple::Mason>. It is designed for zero configuration
and easy install from CPAN.

The "public_html" or "Sites" directory of the user who launched the
process will be used for the document root. Files ending in "html"
are treated as Mason components.

=head1 METHODS

See L<HTTP::Server::Simple> and L<HTTP::Server::Simple::Mason> for
inherited methods.

=head2 CLASS METHODS

=over 4

=item * $class->net_server($newServerType);

Returns the currently active L<Net::Server> subclass.

Sets the server type to the specified Net::Server subclass, if one
is supplied as an argument.

Default value is L<Net::Server::PreFork>.

=item * $class->handler_class($newHandlerClass);

Returns the currently active L<HTML::Mason::Request> subclass.

Sets the server type to the specified HTML::Mason::Request subclass,
if supplied as an argument.

Default value is L<Devel::Pillbug::MasonHandler>.

=back

=head2 INSTANCE METHODS

=over 4

=item * $self->docroot($docroot);

Returns the currently active docroot.

The server will set its docroot to the received absolute path, if
supplied as an argument.

=item * $self->index_name($name);

Returns currently used index name, without extension (default is
"index").

Sets this to the received name, if supplied as an argument.

=item * $self->comp_ext($extension);

Sets the file extension used for Mason components (default is "html")

=item * $self->allow_index($bool);

Returns the current allowed state for directory indexes.

Sets this to the received state, if supplied as an argument.

0 = Off, 1 = On

=back

=head1 CONFIGURATION AND ENVIRONMENT

The document root must exist and be readable, and Devel::Pillbug
must be able to bind to its listen port (default 8080).

=head1 VERSION

This document is for version .005 of Devel::Pillbug.

=head1 AUTHOR

Alex Ayars <pause@nodekit.org>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010, Alex Ayars <pause@nodekit.org>

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl 5.10.0 or later. See:
http://dev.perl.org/licenses/

=head1 SEE ALSO

L<File::HomeDir>, L<File::Type>, L<Net::Server::PreFork>.

This module extends L<HTTP::Server::Simple::Mason>.

=cut
