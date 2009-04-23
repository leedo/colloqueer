package Colloqueer;
use Moose;
use Colloqueer::Channel;
use Glib;
use Gtk2::Gdk::Keysyms;
use YAML::Any;
use FindBin;
use Encode;
use Template;
use XML::LibXML;
use XML::LibXSLT;
use Cwd;

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
  isa => 'POE::Component::IRC',
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

  open my $config_fh, '<', $self->{config};
  my $config = Load(join "\n", <$config_fh>);

  %{ $self->{server} } = %{ $config->{server} };
  $self->nick($config->{nick});
  $self->browser($config->{browser});
  $self->share_dir("$FindBin::Bin/share/");
  $self->theme_dir($self->share_dir . 'styles/' . $config->{theme}
    . '.colloquyStyle/Contents/Resources');

  $self->tt( Template->new(
      ENCODING => 'utf8',
      INCLUDE_PATH => [ $self->share_dir, $self->theme_dir ],));

  $self->style_xsl(
    $self->xslt->parse_stylesheet(
      $self->xml->parse_file($self->theme_dir . '/main.xsl')
    )
  );

  $self->add_channel($_) for @{$config->{channels}};
  $self->window->add($self->notebook);
  $self->window->show_all;
  Glib::Timeout->add(50, sub { $self->display_messages });
  $self->notebook->signal_connect('switch-page', sub {
    my ($notebook, undef, $page) = @_;
    my $channel = $self->channels->[$page];
    Glib::Timeout->add(50, sub {
      $channel->entry->grab_focus;
      return 0;
    });
    $channel->unread(0);
    $channel->icon->set_from_file(
      $self->share_dir . '/images/roomTab.png');
  });
  $self->window->signal_connect('key-press-event', sub {
    my (undef, $event) = @_;
    if ($event->state & "control-mask") {
      if ($event->keyval == $Gtk2::Gdk::Keysyms{n}) {
        $self->notebook->next_page;
        return 1;
      }
      if ($event->keyval == $Gtk2::Gdk::Keysyms{p}) {
        $self->notebook->prev_page;
        return 1;
      }
    }
    return 0;
  });
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

sub format_event {
  my ($self, $event) = @_;
  $self->tt->process('event.xml', {
    event => $event
  }, \(my $xml)) or die $!;
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

1;
