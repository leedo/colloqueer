package Colloqueer::Message;
use Moose;
use Colloqueer::Channel;
use DateTime;
use MIME::Base64 qw/encode_base64/;
use IPC::Open2;

has 'nick' => (isa => 'Str', is => 'ro', required => 1);
has 'hostmask' => (isa => 'Str', is => 'ro', required => 1);
has 'consecutive' => (isa => 'Bool', is => 'rw');
has 'channel' => (isa => 'Colloqueer::Channel', is => 'ro', required => 1);
has 'time' => (isa => 'DateTime', is => 'ro', default => sub { DateTime->now });
has 'text' => (isa => 'Str', is => 'ro', required => 1);
has 'id' => (isa => 'Str', is => 'ro', lazy => 1, default => sub {
  my $self = shift;
  my $id = encode_base64 rand(time) . $self->nick . $self->channel;
  $id =~ s/[\W\s]//g;
  return $id;
});

my $url_re = q{\b(s?https?|ftp|file|gopher|s?news|telnet|mailbox):} .
             q{(//[-A-Z0-9_.]+:\d*)?} .
             q{[-A-Z0-9_=?\#:\$\@~\`%&*+|\/.,;\240]+};

has 'html' => (isa => 'Str', is => 'ro', lazy => 1, default => sub {
  my $self = shift;
  print STDERR "WHAT";
  my $string = $self->text;
  $string =~ s/\\/\\\\/g;
  my $pid = open2 my $out, my $in, "ruby $FindBin::Bin/irc2html.rb";
  print $in $string;
  close $in;
  $string = <$out>;
  $string =~ s/\s{2}/ &#160;/g;
  $string =~ s@($url_re+)@<a href="$1">$1</a>@gi;
  close $out;
  chomp $string;
  wait;
  return $string;
});

1;
