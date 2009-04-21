package Colloqueer::Event;
use Moose;
use Colloqueer::Channel;
use MIME::Base64 qw/encode_base64/;

has 'nick' => (isa => 'Str', is => 'ro', required => 1);
has 'hostmask' => (isa => 'Str', is => 'ro', required => 1);
has 'message' => (isa => 'Str', is => 'ro');
has 'channel' => (isa => 'Colloqueer::Channel', is => 'ro', required => 1);
has 'id' => (isa => 'Str', is => 'ro', lazy => 1, default => sub {
  my $self = shift;
  my $id = encode_base64 rand(time) . $self->nick . $self->channel;
  $id =~ s/[\W\s]//g;
  return $id;
});

1;
