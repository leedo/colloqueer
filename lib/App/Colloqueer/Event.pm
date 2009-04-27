package App::Colloqueer::Event;
use Moose;
use App::Colloqueer::Channel;

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
    return 'a'.time;
  }
);

__PACKAGE__->meta->make_immutable;

1;
