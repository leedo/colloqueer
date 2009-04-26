package Colloqueer::Event;
use Moose;
use Colloqueer::Channel;

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

has 'app' => (
  isa      => 'Colloqueer',
  is       => 'ro',
  weak_ref => 1,
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
    return $self->app->unique_id;
  }
);

__PACKAGE__->meta->make_immutable;

1;
