package Colloqueer;
use Moose;
use Colloqueer::Channel;
use Data::Dumper;
use Glib;
use YAML::Any;
use FindBin;
use Encode;
use Template;
use XML::LibXML;
use XML::LibXSLT;

has 'channel_lookup' => (
  isa => 'HashRef',
  default => sub { {} },
);

has 'channels' => (
  isa => 'ArrayRef[Colloqueer::Channel]',
  is  => 'rw',
  default => sub { [] },
);

has 'irc' => (
  isa => 'Any',
  is => 'ro',
  lazy => 1,
  default => sub {
    my $self = shift;
    my $irc = POE::Component::IRC->spawn( 
      nick      => $self->nick,
      ircname   => $self->ircname,
      port      => $self->server->{port},
      username  => $self->server->{username},
      password  => $self->server->{password},
      server    => $self->server->{host},
    ) or die $!;
  }
);

has 'server' => (isa => 'HashRef', is => 'ro');

has 'window' => (
  isa => 'Gtk2::Window',
  is => 'ro',
  default => sub {
    my $window = Gtk2::Window->new('toplevel');
    $window->set_title('Colloqueer');
    $window->set_default_size(650,500);
    $window->set_border_width(0);
    return $window;
  }
);

has 'notebook' => (
  isa => 'Gtk2::Notebook',
  is => 'ro',
  default => sub {
    my $notebook = Gtk2::Notebook->new;
    $notebook->set_show_tabs(1);
    $notebook->set_tab_pos('bottom');
    return $notebook;
  }
);

has 'tt' => (
  isa => 'Template',
  is  => 'rw',
);

has 'config' => (
  isa      => 'Str',
  required => 1
);

has 'style' => (
  isa => 'Str',
  is  => 'rw'
);

has 'share_dir' => (
  isa => 'Str',
  is  => 'rw',
);

has 'theme_dir' => (
  isa => 'Str',
  is  => 'rw',
);

has 'style_xsl' => (
  isa => 'XML::LibXSLT::StylesheetWrapper',
  is  => 'rw',
);

has 'nick' => (
  isa => 'Str',
  is  => 'rw'
);

has 'ircname' => (
  isa => 'Str',
  is => 'rw',
);

has 'xslt' => (
  isa     => 'XML::LibXSLT',
  is      => 'ro',
  lazy    => 1,
  default => sub {XML::LibXSLT->new()}
);

has 'xml' => (
  isa     => 'XML::LibXML',
  lazy    => 1,
  is      => 'ro',
  default => sub {XML::LibXML->new()}
);

has 'blank_html' => (
  isa => 'Str',
  lazy => 1,
  is => 'ro',
  default => sub {
    my $self = shift;
    $self->tt->process('base.html', undef, \(my $html)); 
    return $html;
  }
);

sub BUILD {
  my $self = shift;

  open my $config_fh, '<', $self->{config};
  my $config = Load(join "\n", <$config_fh>);

  %{ $self->{server} } = %{ $config->{server} };
  $self->nick($config->{nick});
  $self->share_dir("$FindBin::Bin/share");
  $self->theme_dir($self->share_dir . '/styles/'
    . $config->{theme} . '.colloquyStyle/Contents/Resources');

  $self->tt( Template->new(
      ENCODING => 'utf8',
      INCLUDE_PATH => [ $self->share_dir, $self->theme_dir ],));

  $self->style_xsl(
    $self->xslt->parse_stylesheet(
      $self->xml->parse_file($self->theme_dir . '/main.xsl')
    )
  );

  Glib::Timeout->add(100, sub { $self->display_messages });
  $self->add_channel($_) for @{$config->{channels}};
  $self->window->add($self->notebook);
  $self->window->show_all;
}

sub add_channel {
  my ($self, $name) = @_;
  my $channel = Colloqueer::Channel->new( name => $name, app => $self );
  push @{ $self->channels }, $channel;
  $self->{channel_lookup}{$name} = $channel;
}

sub remove_channel {
  my ($self, $channel) = @_;
  $self->irc->yield(part => $channel->name);
  $self->notebook->remove_page($self->notebook->get_current_page);
  for (0 .. $#{ $self->channels }) {
    if ($self->channels->[$_]->name eq $channel->name) {
      splice @{ $self->channels }, $_, 0;
      last;
    }
  }
  delete $self->{channel_lookup}{$channel->name};
}

sub channel_by_name {
  my ($self, $name) = @_;
  return $self->{channel_lookup}{$name};
}

sub show_channel {
  my ($self, $channel_name) = @_;
  my $channel = $self->channels->{$channel_name};
  $self->notebook->append_page($channel->pane, $channel->label);
  $self->window->show_all;
}

sub handle_command {
  my ($self, $command) = @_;
  if ($command =~ /^join (.+)/) {
    $self->irc->yield( join => $1);
    $self->add_channel($1);
  }
  elsif ($command =~ /^part (.+)/) {
    $self->irc->yield( part => $1);
    #$heap->notebook->remove_page($heap->channels->{$1}->page);
  }
}

sub format_messages {
  my ($self, $consecutive, @msgs) = @_;
  my $from = $msgs[0]->{nick};
  $self->tt->process('message.xml', {
    from  => $from,
    msgs  => \@msgs,
    self  => $from eq $self->nick ? 1 : 0,
  }, \(my $message)) or die $!;
  my $doc = $self->xml->parse_string($message,{encoding => 'utf8'});
  my $results = $self->style_xsl->transform($doc,
    XML::LibXSLT::xpath_to_string(
      consecutiveMessage => $consecutive ? 'yes' : 'no',
      fromEnvelope => $consecutive ? 'no' : 'yes',
      bulkTransform => $consecutive ? 'no' : 'yes',
  ));
  $message = $self->style_xsl->output_string($results);
  $message =~ s/<span[^\/>]*\/>//gi; # strip empty spans
  $message =~ s/'/\\'/g;
  $message =~ s/\n//g;
  return decode_utf8($message);

}

sub display_messages {
  my $self = shift;
  $_->display_messages for @{ $self->channels };
  return 1;
}

1;
