package Colloqueer::Event;
use Moose;
use Colloqueer::Channel;
use MIME::Base64 qw/encode_base64/;

has 'nick' => (
  isa      => 'Str',
  is       => 'ro',
  required => 1
);

has 'hostmask' => (
  isa      => 'Str',
  is       => 'ro',
  required => 1
);

has 'message' => (
  isa => 'Str',
  is  => 'ro'
);

has 'channel' => (
  isa      => 'Colloqueer::Channel',
  is       => 'ro',
  required => 1
);

has 'date' => (
  isa     => 'DateTime',
  is      => 'ro',
  default => sub {return DateTime->now}
);

has 'id' => (
  isa     => 'Str',
  is      => 'ro',
  lazy    => 1,
  default => sub {
    my $self = shift;
    return $self->channel->app->unique_id;
  }
);

1;
