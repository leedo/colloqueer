package App::Colloqueer::Message;
use Moose;
use App::Colloqueer::IRC::Formatting;
use DateTime;

has 'nick' => (isa => 'Str', is => 'ro', required => 1);
has 'hostmask' => (isa => 'Str', is => 'ro', required => 1);
has 'consecutive' => (isa => 'Bool', is => 'rw');
has 'time' => (isa => 'DateTime', is => 'ro', default => sub { DateTime->now });
has 'text' => (isa => 'Str', is => 'ro', required => 1);
has 'id' => (isa => 'Str', is => 'ro', lazy => 1, default => sub {
  return 'a'.time;
});

my $url_re = q{\b(s?https?|ftp|file|gopher|s?news|telnet|mailbox):} .
             q{(//[-A-Z0-9_.]+:\d*)?} .
             q{[-A-Z0-9_=?\#:\$\@~\`%&*+|\/.,;\240]+};

has 'html' => (isa => 'Str', is => 'ro', lazy => 1, default => sub {
  my $self = shift;
  my $string = App::Colloqueer::IRC::Formatting->formatted_string_to_html($self->text);
  $string =~ s/\\/\\\\/g;
  $string =~ s/\s{2}/ &#160;/g;
  $string =~ s@($url_re+)@<a href="$1">$1</a>@gi;
  return $string;
});

__PACKAGE__->meta->make_immutable;
1;
