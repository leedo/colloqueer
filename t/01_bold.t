use Test::More tests => 2;

use_ok('App::Colloqueer::IRC::Formatting');
open my $irctext, '<', 't/bold';
my $html = '<span style="">not bold </span><span style="font-weight: bold">bold </span><span style="">not bold</span>';
my $output = App::Colloqueer::IRC::Formatting->formatted_string_to_html(<$irctext>);
ok($output eq $html, 'bolded HTML');
