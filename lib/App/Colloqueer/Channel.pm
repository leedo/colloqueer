package App::Colloqueer::Channel;
use Moose;
use App::Colloqueer;
use App::Colloqueer::Message;
use App::Colloqueer::Event;
use Gtk2::Gdk::Keysyms;
use Gtk2::WebKit;
use Gtk2::Spell;
use Glib qw/TRUE FALSE/;

has 'app' => (
  isa => 'App::Colloqueer',
  is  => 'ro',
  weak_ref => 1,
);

has 'name' => (
  isa      => 'Str',
  is       => 'ro',
  required => 1
);

has 'lastmsg' => (
  isa     => 'App::Colloqueer::Message',
  is      => 'rw',
);

has 'msgs' => (
  isa => 'ArrayRef[App::Colloqueer::Message]',
  is => 'rw',
  default => sub { [] }
);

has 'events' => (
  isa => 'ArrayRef[App::Colloqueer::Event]',
  is => 'rw',
  default => sub { [] }
);

has 'webview' => (
  isa => 'Gtk2::WebKit::WebView',
  is  => 'rw',
  default => sub {Gtk2::WebKit::WebView->new},
);

has 'pane' => (
  isa => 'Gtk2::VPaned',
  is => 'rw',
  default => sub {Gtk2::VPaned->new},
);

has 'entry' => (
  isa => 'Gtk2::TextView',
  is => 'rw',
  lazy => 1,
  default => sub {
    my $tv = Gtk2::TextView->new;
    my $spell = Gtk2::Spell->new_attach($tv);
    $tv->set_pixels_above_lines(3);
    $tv->set_pixels_below_lines(3);
    return $tv;
  }
);

has 'lastnick' => (
  isa => 'Str',
  is => 'rw',
  default => '',
);

has 'active' => (
  isa => 'Bool',
  is => 'rw',
  default => 1,
);

has 'cleared' => (
  isa => 'Bool',
  is => 'rw',
  default => 0,
);

has 'icons' => (
  isa => 'HashRef',
  is => 'ro',
  lazy => 1,
  default => sub {
    my $self = shift;
    {
      roomTab => Gtk2::Image->new_from_file(
        $self->app->share_dir . "/images/roomTab.png"),
      aquaTabClose => Gtk2::Image->new_from_file(
        $self->app->share_dir . "/images/aquaTabClose.png"),
      roomTabNewMessage => Gtk2::Image->new_from_file(
        $self->app->share_dir . "/images/roomTabNewMessage.png")
    }
  }
);

has 'eventbox' => (
  isa     => 'Gtk2::EventBox',
  is      => 'ro',
  default => sub {
    my $self = shift;
    my $eventbox = Gtk2::EventBox->new;
    $eventbox->set_size_request('16', '16');
    $eventbox->signal_connect('button-release-event',
      sub {
        my ($widget,$event,$channel) = @_;
        $channel->active(0);
        $channel->app->remove_channel($channel);
      }, $self);
    $eventbox->signal_connect('enter-notify-event',
      sub { 
        my ($widget,$event,$channel) = @_;
        $channel->update_icon($channel->icons->{aquaTabClose});
      }, $self);
    $eventbox->signal_connect('leave-notify-event',
      sub {
        my ($widget,$event,$channel) = @_;
        my $icon = $channel->unread ? 'roomTabNewMessage' : 'roomTab';
        $channel->update_icon($channel->icons->{$icon});
      }, $self);
    return $eventbox;
  }
);

has 'tabnum' => (
  isa => 'Int',
  is  => 'rw'
);

has 'unread' => (
  isa     => 'Bool',
  is      => 'rw',
  default => 0
);

has 'completion_word' => (
  isa     => 'Str',
  is      => 'rw',
  default => '',
);

has 'completion_index' => (
  isa     => 'Int',
  is      => 'rw',
  default => 0,
);

has 'completion_start_mark' => (
  isa     => 'Int',
  is      => 'rw',
  default => 0,
);

has 'completion_end_mark' => (
  isa     => 'Int',
  is      => 'rw',
  default => 0,
);

sub BUILD {
  my $self = shift;

  $self->webview->signal_connect('navigation-requested' => sub {$self->handle_link_request(@_)});
  $self->webview->signal_connect('populate_popup' => sub {$self->handle_menu_request(@_)});
  $self->entry->signal_connect("key_press_event", sub {$self->handle_input(@_)});
  $self->webview->load_html_string($self->app->blank_html, "file:///".$self->app->theme_dir.'/');
  $self->update_icon($self->icons->{roomTab});

  my $frame = Gtk2::Frame->new;
  $frame->add($self->webview);
  my $frame2 = Gtk2::Frame->new;
  $frame2->add($self->entry);

  $self->pane->pack1($frame, TRUE, FALSE);
  $self->pane->pack2($frame2, FALSE, FALSE);
  $self->tabnum(
    $self->app->notebook->append_page($self->pane, $self->_build_label));
  $self->app->window->show_all;
}

sub handle_link_request {
  my ($self, undef, undef, $req) = @_;
  my $uri = $req->get_uri;
  return if $uri =~ /^member:/;
  my $pid = fork();
  if ($pid == 0) {
    exec($self->app->browser, $uri);
  }
  return 'ignore';
}

sub handle_menu_request {
  my ($self, undef, $menu) = @_;
  for my $menuitem ($menu->get_children) {
    my $label = ($menuitem->get_children)[0];
    next unless $label;
    if ($label->get_text ne 'Open Link'
        and $label->get_text ne 'Copy Link Location'
        and $label->get_text ne 'Copy Image') {
      $menu->remove($menuitem);
    }
  }
}

sub clear {
  my $self = shift;
  $self->webview->load_html_string($self->app->blank_html, '');
  $self->cleared(1);
  return $self;
}

sub handle_input {
  my ($self, $widget, $event) = @_;
  return 0 if $event->state & "shift-mask";
  if ($event->keyval == $Gtk2::Gdk::Keysyms{Return}) {
    my ($start, $end) = $widget->get_buffer->get_bounds;
    my $string = $widget->get_buffer->get_text($start, $end, TRUE);
    return 1 unless $string;
    if ($string =~ /^\/clear/) {
      $self->clear;
    }
    elsif ($string =~ /^\/(.+)/) {
      $self->app->handle_command($1);
    }
    else {
      $self->app->irc->yield(privmsg => $self->name => $string);
      my $msg = App::Colloqueer::Message->new(
        app     => $self->app,
        channel => $self,
        nick    => $self->app->server->{nick},
        hostmask => $self->app->server->{nick}."!localhost",
        text    => $string,
      );
      push @{$self->msgs}, $msg;
      $self->lastmsg($msg);
    }
    $widget->get_buffer->delete($start, $end);
    return 1;
  }
  elsif ($event->keyval == $Gtk2::Gdk::Keysyms{Tab}) {
    my $text = $self->completion_word;
    $text =~ s/^.*\s//;
    my @nicks = sort $self->app->irc->channel_list($self->name);
    $self->completion_index(0) if $self->completion_index > $#nicks;
    for ($self->completion_index .. $#nicks) {
      my $nick = $nicks[$_];
      if (substr($nick,0,length $text) eq $text) {
        my $completion = substr($nick, length $text);
        my $start = $widget->get_buffer->get_iter_at_offset($self->completion_start_mark);
        my $end = $widget->get_buffer->get_iter_at_offset($self->completion_end_mark);
        $widget->get_buffer->delete($start, $end);
        $widget->get_buffer->insert($start, $completion);
        $self->completion_end_mark($self->completion_start_mark + length $completion);
        last;
      }
      $self->completion_index($self->completion_index + 1);
    }
    return 1;
  }
  elsif ($event->state & "control-mask" and $event->keyval == $Gtk2::Gdk::Keysyms{Up}) {
    $widget->get_buffer->set_text($self->lastmsg->text) if $self->lastmsg;
    return 1;
  }
  else {
    my ($start, $end) = $widget->get_buffer->get_bounds;
    my $string = $widget->get_buffer->get_text($start, $end, TRUE) . chr $event->keyval;
    my $buffer = $widget->get_buffer;
    $self->completion_word($string);
    $self->completion_index(0);
    $self->completion_start_mark($buffer->get_property('cursor-position') + 1);
    Gtk2::Spell->get_from_text_view($self->entry)->recheck_all;
    return 0;
  }
}

sub add_message {
  my ($self, $msg) = @_;
  push @{$self->msgs}, $msg;
}

sub add_event {
  my ($self, $msg) = @_;
  push @{$self->events}, $msg;
}

sub clear_events {
  my ($self, $msg) = @_;
  $_ = undef for @{$self->events};
  $self->events([]);
}

sub _build_label {
  my ($self, $messages) = @_;
  my $hbox = Gtk2::HBox->new;
  my $label = Gtk2::Label->new($self->name);
  $hbox->pack_start ($self->eventbox, FALSE, FALSE, 0);
  $hbox->pack_start ($label, TRUE, TRUE, 0);
  $hbox->show_all;
  return $hbox;
}

sub update_icon {
  my ($self, $icon) = @_;
  if ($self->eventbox->child) {
    $self->eventbox->remove($self->eventbox->child);
  }
  $self->eventbox->add($icon);
  $self->eventbox->show_all;
}

sub focused {
  my $self = shift;
  return $self->tabnum == $self->app->notebook->get_current_page;
}

sub display_message {
  my $self = shift;
  return unless $self->active;
  return unless @{ $self->msgs } or @{ $self->events };

  my $title = $self->webview->get_main_frame->get_title;
  return unless $title and $title eq '__empty__';
  
  my $html = '';

  if (my $msg = shift @{ $self->msgs }) {
    my $consecutive = 1 if $msg->nick eq $self->lastnick and ! $self->cleared;
    $self->lastnick($msg->nick);
    $html = $self->app->format_messages($consecutive, $msg);
    $msg = undef;
    $self->cleared(0);
    if (! $self->focused) {
      $self->unread(1);
      $self->update_icon($self->icons->{roomTabNewMessage});
    }
  }
  elsif (@{$self->events}) {
    my @out;
    push @out, $self->app->format_event($_) for @{ $self->events };
    $self->cleared(1);
    $self->clear_events;
    $html = join '', @out;
  }

  $self->webview->execute_script("document.title='$html';");
}

sub handle_quit {
  my ($self, $event) = @_;
  my @nicks = $self->app->irc->channel_list($self->name);
  if (grep {$_ eq $event->nick} @nicks) {
    $self->add_event($event);
  }
}

__PACKAGE__->meta->make_immutable;

1;
