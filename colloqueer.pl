#!/usr/bin/perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/lib";
use Gtk2 qw/-init/;
use POE qw/Component::IRC::State/;
use POE::Kernel { loop => 'Glib' };
use Colloqueer;

$0 = 'colloqueer';

my $app = Colloqueer->new(config => 'config.yaml');

POE::Session->create(
  package_states => [
    main => [ qw/_start irc_001 irc_public/ ],
  ],
  heap => { app => $app },
);

$poe_kernel->run();
exit 0;

sub irc_001 {
  my ($heap, $sender) = @_[HEAP, SENDER];
  for (@{$heap->{app}->channels}) {
    $heap->{app}->irc->yield( join => $_->name);
  }
}

sub irc_public {
  my ($heap, $sender, $who, $where, $what) = @_[HEAP, SENDER, ARG0 .. ARG2];
  my $from = ( split /!/, $who )[0];
  my $channel = $where->[0];
  return unless $heap->{app}->channel_by_name($channel); 
  my $msg = Colloqueer::Message->new(
    nick    => $from,
    text    => $what,
    channel => $heap->{app}->channel_by_name($channel),
  );
  $heap->{app}->channel_by_name($channel)->add_message($msg);
}


sub _start {
  my ($kernel, $session, $heap) = @_[KERNEL, SESSION, HEAP];
  $kernel->signal_ui_destroy( $heap->{app}->window );
  $heap->{app}->irc->yield( register => 'all' );
  $heap->{app}->irc->yield( connect => { } );
}
