package App::Colloqueer;
use Moose;
use App::Colloqueer::Channel;
use Glib;
use Gtk2::Gdk::Keysyms;
use YAML::Any;
use Encode;
use Template;
use XML::LibXML;
use XML::LibXSLT;
use File::ShareDir qw/module_dir dist_dir/;

has 'channel_lookup' => (
  isa => 'HashRef',
  default => sub { {} },
);

has 'channels' => (
  isa => 'ArrayRef[App::Colloqueer::Channel]',
  is  => 'rw',
  default => sub { [] },
);

has 'irc' => (
  isa => 'POE::Component::IRC::State',
  is => 'ro',
  lazy => 1,
  default => sub {
    my $self = shift;
    my $irc = POE::Component::IRC::State->spawn( 
      nick      => $self->server->{nick},
      ircname   => $self->server->{ircname},
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
  is  => 'ro',
);

has 'config' => (
  isa      => 'Str',
  required => 1,
  is       => 'ro',
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
  is  => 'ro',
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

has 'id_counter' => (
  isa => 'Int',
  is => 'rw',
  default => 0,
);

has 'browser' => (
  isa => 'Str',
  is => 'rw',
  default => 'x-www-browser',
);

sub BUILD {
  my $self = shift;

  open my $config_fh, '<', $self->config;
  my $config = Load(join "\n", <$config_fh>);
  close $config_fh;

  %{ $self->{server} } = %{ $config->{server} };
  $self->browser($config->{browser});

  if (-e "$FindBin::Bin/../share/message.xml") {
    $self->share_dir("$FindBin::Bin/../share");
  }
  else {
    $self->share_dir(dist_dir('App-Colloqueer'));
  }
  $self->theme_dir($self->share_dir . '/styles/'
    . $config->{theme} . '.colloquyStyle/Contents/Resources');

  $self->{tt} = Template->new(
      ENCODING => 'utf8',
      INCLUDE_PATH => [ $self->share_dir, $self->theme_dir ]);

  $self->{style_xsl} = 
    $self->xslt->parse_stylesheet(
      $self->xml->parse_file($self->theme_dir . '/main.xsl'));

  $self->window->add($self->notebook);

  $self->notebook->signal_connect('switch-page', sub {
    $self->handle_switch_page(@_)});
  $self->window->signal_connect('key-press-event', sub {
    $self->handle_window_keypress(@_)});

  $self->add_channel($_) for @{$config->{server}{channels}};

  Glib::Timeout->add(100, sub { $self->display_messages });
  $self->window->show_all;
}

sub handle_switch_page {
  my ($self, $notebook, undef, $page) = @_;
  my $channel = $self->channels->[$page];
  return unless $channel;
  Glib::Timeout->add(50, sub {
      $channel->entry->grab_focus;
      return 0;
    });
  if ($channel->unread) {
    $channel->unread(0);
    $channel->update_icon($channel->icons->{roomTab});
  }
}

sub handle_window_keypress {
  my ($self, undef, $event) = @_;
  if ($event->state & "control-mask") {
    if ($event->keyval == $Gtk2::Gdk::Keysyms{n}) {
      $self->notebook->next_page;
      return 1;
    }
    elsif ($event->keyval == $Gtk2::Gdk::Keysyms{p}) {
      $self->notebook->prev_page;
      return 1;
    }
    elsif ($event->keyval == $Gtk2::Gdk::Keysyms{k}) {
      $self->channels->[$self->notebook->get_current_page]->clear();
    }
  }
  return 0;
}

sub add_channel {
  my ($self, $name) = @_;
  my $channel = App::Colloqueer::Channel->new(
    name => $name,
    app  => $self
  );
  push @{ $self->channels }, $channel;
  $self->{channel_lookup}{$name} = $channel;
  $self->irc->yield(names => $name);
  return $channel;
}

sub remove_channel {
  my ($self, $channel) = @_;
  $self->irc->yield(part => $channel->name);
  for (0 .. $#{ $self->channels }) {
    if ($self->channels->[$_]->name eq $channel->name) {
      $self->notebook->remove_page($_);
      splice @{ $self->channels }, $_, 1;
      last;
    }
  }
  delete $self->{channel_lookup}{$channel->name};
}

sub channel_by_name {
  my ($self, $name) = @_;
  return $self->{channel_lookup}{$name};
}

sub handle_command {
  my ($self, $command) = @_;
  if ($command =~ /^join (.+)/) {
    $self->irc->yield( join => $1);
  }
  if ($command =~ /^query (\S+)\s?(.*)/) {
    $self->add_channel($1);
    $self->irc->yield( privmsg => $1 => $2 );
  }
}

sub format_messages {
  my ($self, $consecutive, @msgs) = @_;
  my $from = $msgs[0]->{nick};
  $self->tt->process('message.xml', {
    from  => $from,
    msgs  => \@msgs,
    self  => $from eq $self->server->{nick} ? 1 : 0,
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
  print STDERR "$message\n";
  return decode_utf8($message);
}

sub format_event {
  my ($self, $event) = @_;
  $self->tt->process('event.xml', {
    event => $event
  }, \(my $xml)) or die $!;
  print STDERR "$xml\n\n";
  my $doc = $self->xml->parse_string($xml,{encoding => 'utf8'});
  my $results = $self->style_xsl->transform($doc,
    XML::LibXSLT::xpath_to_string(
      consecutiveMessage => 'no',
      fromEnvelope => 'yes',
      bulkTransform => 'yes',
  ));
  my $html = $self->style_xsl->output_string($results);
  $html =~ s/<span[^\/>]*\/>//gi;
  $html =~ s/'/\\'/g;
  $html =~ s/\n//g;
  return decode_utf8($html);
}

sub display_messages {
  my $self = shift;
  $_->display_message for @{ $self->channels };
  return 1;
}

sub unique_id {
  my $self = shift;
  return 'a' . $self->id_counter($self->id_counter + 1);
}

sub handle_quit {
  my ($self, $event) = @_;
  $_->handle_quit($event) for @{$self->channels};
}

__PACKAGE__->meta->make_immutable;

1;
