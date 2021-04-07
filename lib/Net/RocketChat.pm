package Net::RocketChat;
# ABSTRACT: Implements the REST API for Rocket.Chat
$Net::RocketChat::VERSION = '0.003';
=head1 NAME

Net::RocketChat

=head1 SYNOPSIS

Implements the REST API for Rocket.Chat

=head1 USAGE

You can also specify the username, password and server in the environment variables ROCKETCHAT_USERNAME, ROCKETCHAT_PASSWORD and ROCKETCHAT_SERVER.

Most errors die.  Use eval generously.

   use Net::RocketChat;
   use YAML::XS;
   use strict;

   # specifying connection info directly
   my $chat = Net::RocketChat->new(username => $username, password => $password, server => 'https://your.server.here');
   # or use the environment
   $ENV{ROCKETCHAT_USERNAME} = $username;
   $ENV{ROCKETCHAT_PASSWORD} = $password;
   $ENV{ROCKETCHAT_SERVER} = $server;

   my $chat = Net::RocketChat->new;
   eval {
      $chat->login;
      # DEPRECATED: $chat->join(room => "general");
      my $messages = $chat->messages(room => "general");
      print Dump($messages);
      $chat->send(room => "general",message => "your message goes here");
      $chat->send(room => "general",message => "```\nmulti-line\npastes\nare\nok```");
      # DEPRECATED: $chat->leave(room => "general");
   };
   if ($@) {
      print "caught an error: $@\n";
   }

There are also example scripts in the distribution.

=cut

use Moose;
use Method::Signatures;
use LWP::UserAgent;
use JSON;
use YAML;

=head1 ATTRIBUTES

=over

=item debug

If debug is set, lots of stuff will get dumped to STDERR.

=cut

has 'debug' => (
   is => 'rw',
   default => 0,
);

=item username

If this isn't specified, defaults to $ENV{ROCKETCHAT_USERNAME}

=cut

has 'username' => (
   is => 'rw',
);

=item password

If this isn't specified, defaults to $ENV{ROCKETCHAT_PASSWORD}

=cut

has 'password' => (
   is => 'rw',
);

=item server

The URL for the server, ie. "https://rocketchat.your.domain.here"

If this isn't specified, defaults to $ENV{ROCKETCHAT_SERVER}

=cut

has 'server' => (
   is => 'rw',
);

=item response

Contains the last HTTP response from the server.

=cut

has 'response' => (
   is => 'rw',
);

has 'ua' => (
   is => 'rw',
);

has 'userId' => (
   is => 'rw',
);

has 'authToken' => (
   is => 'rw',
);

has 'rooms' => (
   is => 'rw',
   default => sub { {} },
);

=back

=cut

method BUILD($x) {
   $self->username or $self->username($ENV{ROCKETCHAT_USERNAME});
   $self->password or $self->password($ENV{ROCKETCHAT_PASSWORD});
   $self->server or $self->server($ENV{ROCKETCHAT_SERVER});
   $self->ua(LWP::UserAgent->new);
}

=head1 METHODS

=over

=cut

=item version

Returns the server version.

   {
      "success" : true,
      "version" : "3.12.3"
   }

=cut

method version {
   $self->response($self->ua->get($self->server . "/api/info"));
   if ($self->debug) {
      print STDERR Dump($self->response);
   }
   my $json = decode_json($self->response->content);
   return $json->{version};
}

=item login

Logs in.

=cut

method login {
   $self->response($self->ua->post($self->server . "/api/v1/login",{user => $self->username,password => $self->password}));
   if ($self->debug) {
      print STDERR Dump($self->response);
   }
   my $json = decode_json($self->response->content);
   my $userId = $json->{data}{userId};
   my $authToken = $json->{data}{authToken};
   $self->userId($userId);
   $self->authToken($authToken);
}

=item logout

Logs out.

=cut

method logout {
   $self->get($self->server . "/api/v1/logout");
   if ($self->debug) {
      print STDERR Dump($self->response);
   }
}

=item publicRooms

Fetches a list of rooms, and also stores a mapping of names to ids for future use.  Returns the raw decoded JSON response from the server:

   my $rooms = $chat->publicRooms;

   rooms:
   - _id: GENERAL
     default: !!perl/scalar:JSON::PP::Boolean 1
     lm: 2016-04-30T16:45:32.876Z
     msgs: 54
     name: general
     t: c
     ts: 2016-04-30T04:29:53.361Z
     usernames:
     - someuser
     - someotheruser
   - _id: 8L4QMdEFCYqRH3MNP
     lm: 2016-04-30T21:08:27.760Z
     msgs: 2
     name: dev
     t: c
     ts: 2016-04-30T05:30:59.847Z
     u:
       _id: EBbKeYF9Gvppdhhwr
       username: someuser
     usernames:
     - someuser

=cut

method publicRooms {
   $self->get($self->server . "/api/v1/rooms.get");
   if ($self->debug) {
      print STDERR Dump($self->response);
   }
   my $rooms = decode_json($self->response->content);
   foreach my $room (@{$rooms->{"update"}}) {
     my $n;
     # only private rooms have names
     if (defined $room->{name}) {
       $n = $room->{name}
     } else {
       $n = $room->{_id}
     }
     $self->{rooms}{$n}{id} = $room->{_id};
   }

   $self->{rooms_cached} = 1;

   return $rooms->{"update"};
}

=item getRooms

Returns a list of rooms and their names.

=cut

method getRooms {
    if (not $self->{rooms_cached})
    {
      $self->publicRooms;
    }

    return $self->{rooms};
}

=item has_room(:$room)

Returns 1 if a room exists on the server, 0 otherwise.

   if ($chat->has_room("general") {
      $chat->send(room => "general", message => "Hello, world!");
   }
   else {
      ...
   }

=cut

method has_room(:$room) {
   #print "DEBUG-HR: $room\n";
   eval {
      $self->get_room_id(room => "$room");
   };
   if ($@) {
      return 0;
   }
   else {
      return 1;
   }
}

=item join(:$room,:$room)

DEPRECATED for rooms?

Joins a room.  Rooms have a human readable name and an id.  You can use either, but if the name isn't known it will automatically fetch a list of rooms.

   $chat->join(room => "general");

See: https://developer.rocket.chat/api/rest-api/methods/channels/join

=cut

method join(:$id,:$room) {
   $id //= $self->get_room_id(room => "$room");
   $self->post($self->server . "/api/v1/channels.join?roomId=$id");
   if ($self->debug) {
      print STDERR Dump($self->response);
   }
}

=item leave(:$id,:$room)

Leaves a room/channel (NEEDS CLARIFICATION), specified either by name or id.

   $chat->leave(room => "general");

See: https://developer.rocket.chat/api/rest-api/methods/channels/leave
See: https://developer.rocket.chat/api/rest-api/methods/rooms/leave

=cut

method leave(:$id,:$room) {
   $id //= $self->get_room_id(room => "$room");
#   $self->post($self->server . "/api/v1/channels.leave?roomId=$id");
   $self->post($self->server . "/api/v1/rooms.leave?roomId=$id");
   if ($self->debug) {
      print STDERR Dump($self->response);
   }
}

=item messages(:$room,:$id)

Gets all the messages from a room, specified either by name or id.

   my $messages = $chat->messages(room => "general");

=cut

method messages(:$id,:$room) {
   $id //= $self->get_room_id(room => "$room");
   $self->get($self->server . "/api/v1/im.history?roomId=$id\&count=10000");
   if ($self->debug) {
      print STDERR Dump($self->response);
   }
   return decode_json($self->response->content);
}

=item files(:$room,:$id)

Gets all the files from a room, specified either by name or id.

   my $files = $chat->files(room => "general");

=cut

method files(:$id,:$room) {
   $id //= $self->get_room_id(room => "$room");
   $self->get($self->server . "/v1/im.files?roomId=$id");
   if ($self->debug) {
      print STDERR Dump($self->response);
   }
   return decode_json($self->response->content);
}

=item getFile($fileURL)

Downloads an attached file from a message, specified by the fileURL.

   my $file = $chat->getFile("file-upload/pJtGHynLYC7zt8uaW/2021-03-24T10:15:56.485Z");

=cut

method getFile($fileURL) {
   $self->get($self->server . "$fileURL");
   if ($self->debug) {
      print STDERR Dump($self->response);
   }
   return $self->response->content;
}

=item send(:$room,:$id,:$message)

method NEEDS TO BE UPDATED to the new API

The appropriate new API calls are most likely: chat.sendMessage or chat.postMessage

Sends a message to a room.

   $chat->send(room => "general", message => "Hello, world!");

=cut

method send(:$room,:$id,:$message) {
   $id //= $self->get_room_id(room => "$room");
   my $msg = {
      msg => $message,
   };
   $self->post($self->server . "/api/v1/rooms/$id/send",encode_json($msg));
   if ($self->debug) {
      print STDERR Dump($self->response);
   }
   return 1;
}

# looks up a room's internal id or fetches from the server if it couldn't be found.  throws an exception if it's an invalid room name.
method get_room_id(:$room) {
    #print "DEBUG-GRI: $room\n";
   if (not exists $self->{rooms}{$room}) {
      print STDERR "couldn't find room $room, checking server\n" if ($self->debug);
      $self->publicRooms;
   }
   if (not exists $self->{rooms}{$room}) {
      die "invalid_room";
   }
   return $self->{rooms}{$room}{id};
}

# convenience method that stuffs in some authentication headers into a GET request
method get($url) {
   $self->response($self->ua->get($url,"X-Auth-Token" => $self->authToken, "X-User-Id" => $self->userId));
   $self->response->is_error and die "http_error";
}

# convenience method that stuffs in some authentication headers into a POST request
method post($url,$content) {
   $self->response($self->ua->post($url,"X-Auth-Token" => $self->authToken, "X-User-Id" => $self->userId, "Content-Type" => "application/json", Content => $content));
   $self->response->is_error and die "http_error";
}

=back

=head1 AUTHOR

Dale Evans, C<< <daleevans@github> >> L<http://devans.mycanadapayday.com>

2021: Adaptation to the new API: Andy Spiegl, C<< <a.spiegl+rocketchat@lmu.de> >>

=head1 REPOSITORY

L<https://github.com/daleevans/perl-Net-RocketChat>

=head1 SEE ALSO

L<Developer Guide (REST API)|https://developer.rocket.chat/api/rest-api>

=cut

1;

