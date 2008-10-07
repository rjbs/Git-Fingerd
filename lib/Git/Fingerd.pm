use strict;
use warnings;
package Git::Fingerd;
use Net::Finger::Server 0.003;
BEGIN { our @ISA = qw(Net::Finger::Server); }
# ABSTRACT: let people finger your git server for... some reason

use List::Util qw(max);
use SUPER;
use String::Truncate qw(elide);
use Text::Table;

=head1 DESCRIPTION

This module implements a simple C<finger> server that describes the contents of
a server that hosts git repositories.  You can finger C<@servername> for a
listing of repositories and finger C<repo@servername> for information about
a single repository.

This was meant to provide a simple example for Net::Finger::Server, but enough
people asked for the code that I've released it as something reusable.  Here's
an example program using Git::Fingerd:

  #!/usr/bin/perl
  use Git::Fingerd -run => {
    isa     => 'Net::Server::INET',
    basedir => '/var/lib/git',
  };

This program could then run out of F<xinetd>.

=cut

sub new {
  my ($class, %config) = @_;

  my $basedir = delete $config{basedir} || Carp::croak('no basedir supplied');
  my $self = $class->SUPER(%config, log_level => 0);
  $self->{__PACKAGE__}{basedir} = $basedir;

  return $self;
}

sub basedir { $_[0]->{__PACKAGE__}{basedir} }

sub username_regex { qr{[-a-z0-9]+}i   }

sub listing_reply {
  my $basedir = $_[0]->basedir;
  my @dirs = sort <$basedir/*>;

  my $table = Text::Table->new('Repository', '  Description');

  my %repo;

  for my $i (reverse 0 .. $#dirs) {
    my $dir = $dirs[$i];
    my $mode = (stat $dir)[2];
    unless ($mode & 1) {
      splice @dirs, $i, 1;
      next;
    }

    my $repo = $dir;
    s{\A$basedir/}{}, s{\.git\z}{} for $repo;
    my $desc = `cat $dir/description`;
    chomp $desc;

    $repo{ $repo } = $desc;
  }

  my $desc_len = 79 - 3 - (List::Util::max map { length } keys %repo);

  for my $repo (sort { lc $a cmp lc $b } keys %repo) {
    $table->add($repo => '  ' . elide($repo{$repo}, $desc_len));
  }

  return "$table";
}

sub user_reply {
  my ($self, $username, $arg) = @_;

  my $basedir = $self->basedir;
  my $dir = "$basedir/$username.git";

  return "unknown repository\n" unless -d $dir;

  my $mode = (stat $dir)[2];

  return "unknown repository\n" unless $mode & 1;

  my $cloneurl = -f "$dir/cloneurl"    ? `cat $dir/cloneurl`    : '(none)';
  my $desc     = -f "$dir/description" ? `cat $dir/description` : '(none)';
  chomp($cloneurl, $desc);

  my $reply = <<"END_DESC";
Project  : $username
Desc.    : $desc
Clone URL: $cloneurl
END_DESC

  return $reply;
}

1;
