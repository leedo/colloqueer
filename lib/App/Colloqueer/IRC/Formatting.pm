package App::Colloqueer::IRC::Formatting;

use List::MoreUtils qw/natatime/;
use Moose;
use HTML::Entities;

use feature qw/:5.10/;

my $BOLD      = "\002",
my $COLOR     = "\003";
my $RESET     = "\017";
my $INVERSE   = "\026";
my $UNDERLINE = "\037";

my $COLOR_SEQUENCE    = qr/(\d{0,2})(?:,(\d{0,2}))?/;
my $COLOR_SEQUENCE_NC = qr/\d{0,2}(?:,\d{0,2})?/;
my $FORMAT_SEQUENCE   = qr/(
      $BOLD
    | $COLOR$COLOR_SEQUENCE_NC?
    | $RESET
    | $INVERSE
    | $UNDERLINE)
    /x;

my @COLORS = ( qw/fff 000 008 080 ff0 800 808 f80
         ff0 0f0 088 0ff 00f f0f 888 ccc/ );

has 'b' => (
  is => 'rw',
  isa => 'Bool',
  default => 0,
);

has 'i' => (
  is => 'rw',
  isa => 'Bool',
  default => 0,
);

has 'u' => (
  is => 'rw',
  isa => 'Bool',
  default => 0,
);

has 'fg' => (
  is => 'rw',
  isa => 'Any',
);

has 'bg' => (
  is => 'rw',
  isa => 'Any',
);

sub dup {
  my $self = shift;
  return App::Colloqueer::IRC::Formatting->new(
    b => $self->b,
    i => $self->i,
    u => $self->u,
    fg => $self->fg,
    bg => $self->bg,
  )
}

sub reset {
  my $self = shift;
  $self->b(0);
  $self->i(0);
  $self->u(0);
  $self->fg('');
  $self->bg('');
}

sub accumulate {
  my ($self, $format_sequence) = @_;
  given ($format_sequence) {
    when (/$BOLD/) {
      $self->b = !$self->b;
    }
    when (/$UNDERLINE/) {
      $self->u = !$self->u;
    }
    when (/$INVERSE/) {
      $self->i = !$self->i;
    }
    when (/$RESET/) {
      $self->reset;
    }
    when (/$COLOR/) {
      my ($fg, $bg) = $self->_extract_colors_from($format_sequence);
      $self->fg($fg);
      $self->bg($bg);
    }
  }
  return $self->dup;
}

sub to_css {
  my $self = shift;
  my @properties;
  my %styles = %{ $self->_css_styles };
  for (keys %styles) {
    push @properties, "$_: $styles{$_}";
  }
  return join ";", @properties;
}

sub _extract_colors_from {
  my ($self, $format_sequence) = @_;
  $format_sequence = substr($format_sequence, 1);
  my ($fg, $bg) = ($format_sequence =~ /$COLOR_SEQUENCE/);
  if (!$fg) {
    return undef, undef;
  }
  else {
    return $fg, $bg || $self->bg;
  }
}

sub _css_styles {
  my $self = shift;
  my ($fg, $bg) = $self->i ? ($self->bg || 0, $self->fg || 1) : ($self->fg, $self->bg);
  my $styles = {};
  $styles->{'color'} = '#'.$COLORS[$fg] if $fg;
  $styles->{'background-color'} = '#'.$COLORS[$bg] if $bg;
  $styles->{'font-weight'} = 'bold' if $self->b;
  $styles->{'text-decoration'} = 'underline' if $self->u;
  return $styles;
}

sub formatted_string_to_html {
  my ($class, $string) = @_;
  my @lines;
  for (split "\n", $string) {
    my @formatted_line = parse_formatted_string($_);
    my $line;
    for (@formatted_line) {
      $line .= '<span style="'.$_->[0]->to_css.'">'.encode_entities($_->[1]).'</span>';
    }
    push @lines, $line;
  }
  return join "\n", @lines;
}

sub parse_formatted_string {
  my $line = shift;
  print STDERR $line;
  my @segments;
  my $it = natatime 2, ("", split(/$FORMAT_SEQUENCE/, $line));
  my $formatting = App::Colloqueer::IRC::Formatting->new;
  while (my ($format_sequence, $text) = $it->()) {
    $formatting = $formatting->accumulate($format_sequence);
    push @segments, [ $formatting, $text];
  }
  return @segments;
}

1;
