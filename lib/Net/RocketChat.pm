package Net::RocketChat;
# ABSTRACT: Implements the REST API for Rocket.Chat
$Net::RocketChat::VERSION = '0.007';
=head1 NAME

Net::RocketChat

=head1 SYNOPSIS

Implements the REST API for Rocket.Chat

=head1 USAGE

Necessary config data:
 - RocketChat servername:
    Named hash "server" or environment variable ROCKETCHAT_SERVER

 - Username:
    Named hash "username" or environment variable ROCKETCHAT_USERNAME

 - Password:
    Named hash "password" or environment variable ROCKETCHAT_PASSWORD

 - As alternative to a password you can authenticate with USERID and AUTHTOKEN
    You can get these inside your RocketChat user profile.
    Then you specify USERID and AUTHTOKEN as named hashes or as environment variables ROCKETCHAT_USERID and ROCKETCHAT_AUTHTOKEN.

Most errors die.  Use eval generously.

   use Net::RocketChat;
   use YAML::XS;
   use strict;

   my $chat;

   # specifying connection info directly
   $chat = Net::RocketChat->new(username => $username, password => $password, server => 'https://your.server.here');
   # or as userid + authtoken
   $chat = Net::RocketChat->new(userid => $userid, authtoken => $authtoken, server => 'https://your.server.here');

   # or use the environment
   $ENV{ROCKETCHAT_USERNAME} = $username;
   $ENV{ROCKETCHAT_PASSWORD} = $password;
   $ENV{ROCKETCHAT_SERVER} = $server;

   $ENV{ROCKETCHAT_USERID} = $userid;
   $ENV{ROCKETCHAT_AUTHTOKEN} = $authtoken;

   my $chat = Net::RocketChat->new;
   eval {
      $chat->login;
      $myrooms=$chat->getMyRooms;
      my $messages = $chat->messages(room => "general");
      print Dumper($messages);

      # TODO: join not implemented for new API
      #$chat->join(room => "general");
      # TODO: send not implemented for new API
      #$chat->send(room => "general",message => "your message goes here");
      #$chat->send(room => "general",message => "```\nmulti-line\npastes\nare\nok```");
      $chat->leave(room => "general");
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
#use YAML;
use Data::Dumper;

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

=item userId

If this isn't specified, defaults to $ENV{ROCKETCHAT_USERID}

=cut

has 'userId' => (
   is => 'rw',
);

=item authToken

If this isn't specified, defaults to $ENV{ROCKETCHAT_AUTHTOKEN}

=cut

has 'authToken' => (
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

has 'rooms' => (
   is => 'rw',
   default => sub { {} },
);

=item roomcount

Contains the numbers of cached (joined) rooms.
Initialized during first getMyRoomsFull call.

=cut

has 'roomcount' => (
   is => 'rw',
);

=item specialMsg

A list of detailed descriptions of special messages.
Like "user added", "room topic changed".

For a full list, see these files in the source code of Rocketchat:

=over 4

=item - app/lib/lib/MessageTypes.js

=item - client/startup/messageTypes.ts

=item - packages/rocketchat-i18n/i18n/en.i18n.json

=item - packages/rocketchat-i18n/i18n/de.i18n.json

=back

=cut

has 'specialMsg' => (
   is => 'rw',
   default => sub { {
                     'wm' => 'Welcome, __N__',
                     'rm' => '[Message removed]',
                     'r'  => '[Room name changed by __N__ to: __T__]',
                     't'  => '[Room name changed by __N__ to: __T__]',
                     'au' => '[User added by __N__: __T__]',
                     'ru' => '[Removed user by __N__: __T__]',
                     'ut' => '[__N__ (__T__) has joined the conversation]',
                     'uj' => '[__N__ (__T__) has joined the channel]',
                     'ujt' => '[__N__ (__T__) has joined the team]',
                     'ul' => '[__N__ has left the channel]',
                     'ult' => '[__N__ (__T__) has left the team]',
                     'user-muted' => '[User __T__ muted by __N__]',
                     'user-unmuted' => '[User __T__ unmuted by __N__]',
                     'subscription-role-added' => '[__T__ was set __R__ by __N__]',
                     'subscription-role-removed' => '[__T__ is no longer __R__ by __N__]',
                     'room_changed_description' => '[Room description by __N__ changed to: __T__]',
                     'room_changed_topic' => '[Room topic changed by __N__ to: __T__]',
                     'room_changed_avatar' => '[Room avatar changed by __N__]',
                     'room_changed_announcement' => '[Room announcement changed by __N__ to: __T__]',
                     'room_changed_privacy' => '[Room type changed by __N__ to: __T__]',
                     'message_pinned' => '[Pinned a message]',
                     'jitsi_call_started' => '[Started a video call]',
                     'discussion-created' => '[discussion created: __T__]',
                   }
                  },
);

=back

=cut

method BUILD($x) {
   $self->server or $self->server($ENV{ROCKETCHAT_SERVER});
   $self->username or $self->username($ENV{ROCKETCHAT_USERNAME});
   $self->password or $self->password($ENV{ROCKETCHAT_PASSWORD});
   $self->userId or $self->userId($ENV{ROCKETCHAT_USERID});
   $self->authToken or $self->authToken($ENV{ROCKETCHAT_AUTHTOKEN});
   $self->ua(LWP::UserAgent->new);

   $self->username or die "ERROR: missing config variable server";
   $self->username or die "ERROR: missing config variable username";

   # remove trailing slash
   if ($self->server =~ m|/$|)
   {
     my $sv = $self->server;
     $sv =~ s|/$||;
     $self->server($sv);
   }
}

=head1 METHODS

=over

=cut

=item version

Returns the server version.  No user login necessary.

   { "version" : "3.12.3" }

=cut

method version {
   $self->response($self->ua->get($self->server . "/api/info"));
   if ($self->debug) {
      print STDERR Dumper($self->response);
   }
   my $json = decode_json($self->response->content);
   return $json->{version};
}

=item login

Logs in.

=cut

method login {
  # already logged in?
  if ($self->userId and $self->authToken)
  {
    return;
  }

   $self->response($self->ua->post($self->server . "/api/v1/login",{user => $self->username,password => $self->password}));
   $self->response->is_error and die "ERROR: login_error";

   if ($self->debug) {
      print STDERR Dumper($self->response);
   }
   my $json = decode_json($self->response->content);
  if (not $json->{data}{userId} or not $json->{data}{authToken})
  {
    die "ERROR: login failed";
  }
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
      print STDERR Dumper($self->response);
   }
}

=item getUserInfo(:$username,:$userid)

Gets all user details, specified either by username or id.

   my $userinfo = $chat->getUserInfo(username => "ab123cde");

=cut

method getUserInfo(:$username,:$userid) {
   if (not $userid and not $username)
   {
     die "ERROR: getUserInfo needs either userid or username";
   }

   if ($username)
   {
     $self->get($self->server . "/api/v1/users.info?username=$username");
   }
   else
   {
     $self->get($self->server . "/api/v1/users.info?userId=$userid");
   }

   if ($self->debug) {
      print STDERR Dumper($self->response);
   }
   return decode_json($self->response->content)->{"user"};
}

=item getMyRooms

Fetches a list of (joined) rooms, and also stores the room type and a mapping of names to ids for future use.

Returns the raw decoded JSON response from the server.
Use method getMyRooms to get the digested list.

Room types:
    d: Direct chat ("im")
    c: Open chat ("channel" hash-symbol)
    p: Private chat ("group" lock-symbol)
    l: Livechat ("omnichannel")

   my $rooms = $chat->getMyRoomsFull;

=cut

method getMyRoomsFull {
    if ($self->{rooms_cached})
    {
      return $self->{rooms_cached};
    }

   my $rooms;

   $self->get($self->server . "/api/v1/rooms.get");
   if ($self->debug) {
     print STDERR Dumper($self->response);
   }
   $rooms = decode_json($self->response->content);

   foreach my $room (@{$rooms->{"update"}}) {
     my ($rType, $rName);

     $rType = $room->{t};
     if ($rType eq 'd')          # Direct Chat (im)
     {
       # "chat" with myself
       if ($room->{usersCount} == 1)
       {
         $rName = $self->username;
       }

       # 1:1 direct chat
       elsif ($room->{usersCount} == 2)
       {
         # find username of the other user
         foreach my $u (@{$room->{"usernames"}})
         {
           next if $u eq $self->username;
           $rName = $u;
         }
       }

       # multi-user direct chat
       else
       {
         # TODO
         $rName = $room->{_id};    # dumb interim solution
       }

       $self->{rooms}{$rName}{userscount} = $room->{usersCount};
     }

     elsif ($rType eq 'c')          # Open Chat (channel)
     {
       $rName = $room->{fname}  if $room->{fname};
       $rName //= $room->{name};
       $self->{rooms}{$rName}{userscount} = $room->{usersCount};
       $self->{rooms}{$rName}{creator} = $room->{u}->{username};
       $self->{rooms}{$rName}{topic} = $room->{topic}  if $room->{topic}; # optional
       $self->{rooms}{$rName}{description} = $room->{description}  if $room->{description}; # optional
       $self->{rooms}{$rName}{announcement} = $room->{announcement}  if $room->{announcement}; # optional

       # for debugging (not documented in Rocketchat scheme)
       print STDERR "WARNING: room $rName: fname != name\n"  if $room->{fname} and $room->{fname} ne $rName;
     }

     elsif ($rType eq 'p')          # Private Chat (group)
     {
       $rName = $room->{fname}  if $room->{fname};
       $rName //= $room->{name};
       $self->{rooms}{$rName}{userscount} = $room->{usersCount};
       $self->{rooms}{$rName}{creator} = $room->{u}->{username};
       $self->{rooms}{$rName}{topic} = $room->{topic}  if $room->{topic}; # optional

       # for debugging (not documented in Rocketchat scheme)
       print STDERR "WARNING: room $rName: fname != name\n"  if $room->{fname} and $room->{fname} ne $rName;
     }

     elsif ($rType eq 'l')          # Livechat (omnichannel)
     {
       # (not documented in Rocketchat scheme)
       # TODO
       $rName = $room->{_id};   # dumb interim solution
     }

     $self->{rooms}{$rName}{id} = $room->{_id};
     $self->{rooms}{$rName}{type} = $rType;

     $self->{roomcount}++;
   }

   # save complete hash for later re-use
   $self->{rooms_cached} = $rooms->{"update"};

   # return complete hash (use method getMyRooms if you want the digested list)
   return $rooms->{"update"};
}

=item getMyRooms

Returns a digested list of (joined) rooms with their types, names and some other interesting info about them.

Room types:
    d: Direct chat ("im")
    c: Chat ("channel" hash-symbol)
    p: Private chat ("group" lock-symbol)
    l: Livechat ("omnichannel")

   my $rooms = $chat->getMyRooms;

=cut

method getMyRooms {
    if (not $self->{rooms_cached})
    {
      $self->getMyRoomsFull;
    }

    return $self->{rooms};
}

=item getMyRoomsCount

Returns the number of joined room.

=cut

method getMyRoomsCount {
    return $self->{roomcount};
}

=item getMyChannelsFull

Fetches a list of (joined) channels with all information.

Returns the raw decoded JSON response from the server.
Use method getMyRooms and filter for type 'c' to get a digested list of channels.

=cut

method getMyChannelsFull {
   $self->get($self->server . "/api/v1/channels.list.joined");
   if ($self->debug) {
      print STDERR Dumper($self->response);
   }
   my $channels = decode_json($self->response->content);

   return $channels->{"channels"};
}

=item getMyGroupsFull

Fetches a list of (joined) groups with all information.

Returns the raw decoded JSON response from the server.
Use method getMyRooms and filter for type 'p' to get a digested list of groups.

=cut

method getMyGroupsFull {
   $self->get($self->server . "/api/v1/groups.list");
   if ($self->debug) {
      print STDERR Dumper($self->response);
   }
   my $groups = decode_json($self->response->content);

   return $groups->{"groups"};
}

=item getMyDirectFull

Fetches a list of (joined) direct chats with all information.

Returns the raw decoded JSON response from the server.
Use method getMyRooms and filter for type 'd' to get a digested list of direct chats.

=cut

method getMyDirectFull {
   $self->get($self->server . "/api/v1/im.list");
   if ($self->debug) {
      print STDERR Dumper($self->response);
   }
   my $ims = decode_json($self->response->content);

   return $ims->{"ims"};
}

=item has_room(:$room)

Returns 1 if a room exists on the server, 0 otherwise.

   if ($chat->has_room("general") {
      $chat->messages(room => "general");
   }

=cut

method has_room(:$room) {
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

=item join(:$id)

NOT IMPLEMENTED YET

Joins a room/channel/group/im, specified either by its id.

   $chat->join(room => "general");

See: https://developer.rocket.chat/api/rest-api/methods/channels/join
See: https://developer.rocket.chat/api/rest-api/methods/groups/open
See: https://developer.rocket.chat/api/rest-api/methods/im/create

=cut

method join(:$id,:$room) {
  die "ERROR: NOT IMPLEMENTED YET";

#   $self->post($self->server . "/api/v1/channels.join?roomId=$id");
#   $self->post($self->server . "/api/v1/groups.open?roomId=$id");
#   $self->post($self->server . "/api/v1/im.create?user=$id");

#   if ($self->debug) {
#      print STDERR Dumper($self->response);
#   }
}

=item leave(:$id,:$room)

NOT IMPLEMENTED YET

Leaves a room/channel/group/im, specified either by name or id.

   $chat->leave(room => "general");

See: https://developer.rocket.chat/api/rest-api/methods/channels/leave
See: https://developer.rocket.chat/api/rest-api/methods/groups/leave
See: https://developer.rocket.chat/api/rest-api/methods/im/close
See: https://developer.rocket.chat/api/rest-api/methods/rooms/leave

=cut

method leave(:$id,:$room) {
  die "ERROR: NOT IMPLEMENTED YET";

   if (not $id and not $room)
   {
     die "ERROR: leave needs either id or roomname";
   }
   $id //= $self->get_room_id(room => "$room");
   $room //= $self->get_room_name(id => "$id");
#   $self->post($self->server . "/api/v1/channels.leave?roomId=$id");
#   $self->post($self->server . "/api/v1/groups.leave?roomId=$id");
#   $self->post($self->server . "/api/v1/rooms.leave?roomId=$id");
#   $self->post($self->server . "/api/v1/im.close?roomId=$id");

#   if ($self->debug) {
#      print STDERR Dumper($self->response);
#   }
}

=item getRoomMessages(:$room,:$id)

Gets all (up to 10000) the messages from a room, specified either by name or id.

   my $messages = $chat->getRoomMessages(room => "general");

=cut

method getRoomMessages(:$id,:$room) {
   if (not $id and not $room)
   {
     die "ERROR: getRoomMessages needs either id or roomname";
   }
   $id //= $self->get_room_id(room => "$room");
   $room //= $self->get_room_name(id => "$id");

   my $rName = $room;
   my $rType = $self->get_room_type(room => "$room");

   if ($rType eq 'd')          # Direct Chat (im)
   {
     $self->get($self->server . "/api/v1/im.history?roomId=$id\&count=10000");
   }

   elsif ($rType eq 'c')          # Open Chat (channel)
   {
     $self->get($self->server . "/api/v1/channels.history?roomId=$id\&count=10000");
   }

   elsif ($rType eq 'p')          # Private Chat (group)
   {
     $self->get($self->server . "/api/v1/groups.history?roomId=$id\&count=10000");
   }

   elsif ($rType eq 'l')          # Livechat (omnichannel)
   {
     # TODO
     return "";                 # dumb interim solution
   }

   if ($self->debug) {
      print STDERR Dumper($self->response);
   }
   return decode_json($self->response->content)->{messages};
}

=item processMessageType(:$msg, :$msgText, :$name)

Change the message text if the message has a special message type.

   my $user = $msg->{u}->{name};
   my $text = $msg->{msg};
   $details = $chat->processMessageType(msgText => $text, msg => $msg, name => $user);

=cut

method processMessageType(:$msg, :$msgText, :$name) {
  my $msgTextNew;
  my $specialMsg = $self->specialMsg;

  # not a special message type -> nothing to do
  if (not $msg->{t})
  {
    return $msgText;
  }

  if (not $specialMsg->{ $msg->{t} } )
  {
    print STDERR "WARNING: unknown message type \"", $msg->{t} ,"\".\n";
  }

  $msgTextNew = $specialMsg->{ $msg->{t} };
  $msgTextNew =~ s/__T__/$msgText/g;
  $msgTextNew =~ s/__N__/$name/g;
  $msgTextNew =~ s/__R__/$msg->{role}/g;

  return $msgTextNew;
}

=item getFilesList(:$room,:$id)

Gets a list of all the files from a room, specified either by name or id.

   my $files = $chat->getFilesList(room => "general");

=cut

method getFilesList(:$id,:$room) {
   if (not $id and not $room)
   {
     die "ERROR: getFiles needs either id or roomname";
   }
   $id //= $self->get_room_id(room => "$room");
   $room //= $self->get_room_name(id => "$id");

   $self->get($self->server . "/api/v1/im.files?roomId=$id");
   if ($self->debug) {
      print STDERR Dumper($self->response);
   }
   return decode_json($self->response->content);
}

=item getFile($fileURL)

Downloads an attached file from a message, specified by the fileURL.

   my $file = $chat->getFile($fileURL => "file-upload/pJtGHynLYC7zt8uaW/2021-03-24T10:15:56.485Z");

=cut

method getFile(:$fileURL) {
  print STDERR "DEBUG: downloading file: ", $self->server . "$fileURL", "\n"  if ($self->debug);
   $self->get($self->server . "$fileURL");
   if ($self->debug) {
      print STDERR Dumper($self->response);
   }
   return $self->response->content;
}

=item saveAttachment(:$att, :$downloadFolder)

Downloads and saves an attached file from a message, specified by the fileURL.
Tries to find a good filename and file extension.

Returns the filename and the MIME type, e.g. "image/gif".

   my ($filename, $filetype) = $chat->saveAttachment(att => $attachmentObject, downloadFolder => "savedFiles);

=cut

method saveAttachment(:$att, :$downloadFolder) {
  my ($fn, $ft);

  # without an URL we cannot download the attachment
  if (not $att->{title_link})
  {
    die "ERROR: no download URL for attachment - skipping\n";
  }

  # find a good filename: start out with the attachment title
  if ($att->{title})
  {
    $fn = $att->{title};
  }
  else
  {
    $fn = $att->{title_link};
    $fn =~ m|.*?([^/]+)$|;      # filename part of the URL
    $fn = $1;
  }
  # sanitize filename a bit
  $fn =~ s/ /_/g;             # spaces in filenames are inconvenient
  $fn =~ s/:/-/g;             # Windows doesn't like : in filenames

  unless ($fn)
  {
    die "ERROR: Cannot save attachment without a filename.\n";
  }

  # try to find out the filetype (guessing because of missing RC documentation)
  if ($att->{image_type})
  {
    $ft = $att->{image_type};
  }
  elsif ($att->{video_type})
  {
    $ft = $att->{video_type};
  }
  elsif ($att->{audio_type})
  {
    $ft = $att->{audio_type};
  }
  else
  {
    $ft = '';                   # unknown filetype
  }

  print STDERR "DEBUG: attachment URL: ", $att->{title_link}, "\n"  if ($self->debug);

  # work around missing RC documentation
  if ($att->{image_url} and $att->{image_url} ne $att->{title_link})
  {
    my ($i, $t);
    $i = $att->{image_url};
    $t = $att->{title_link};
    $i =~ s|.*/||;  # remove leading path
    $t =~ s|.*/||;  # remove leading path

    # only warn if the filename (not path) itself is different
    if ($i ne $t)
    {
      print STDERR " (WARNING: image_url (", $att->{image_url}, ") different from title_link: ", $att->{title_link}, ")";
    }
  }
  if ($att->{audio_url} and $att->{audio_url} ne $att->{title_link})
  {
    print STDERR " (WARNING: audio_url (", $att->{audio_url}, ") different from title_link: ", $att->{title_link}, ")";
  }
  if ($att->{video_url} and $att->{video_url} ne $att->{title_link})
  {
    print STDERR " (WARNING: video_url (", $att->{video_url}, ") different from title_link: ", $att->{title_link}, ")";
  }

  # detect file extension (in a not very smart way.  TODO: improve!)
  my $fext='';
  if ($ft eq '') {
    # no filetype given - guess
    if ($att->{title_link} =~ /\.txt$/)
    { $ft='plain/text'; $fext='txt'; }
    elsif ($att->{title_link} =~ /\.zip$/)
    { $ft='application/zip'; $fext='zip'; }
    elsif ($att->{title_link} =~ /\.pdf$/)
    { $ft='application/pdf'; $fext='pdf'; }
    elsif ($att->{title_link} =~ /\.7z$/)
    { $ft='application/7zip'; $fext='7z'; }
    elsif ($att->{title_link} =~ /\.xlsx$/)
    { $ft='application/word'; $fext='docx'; }
    elsif ($att->{title_link} =~ /\.docx$/)
    { $ft='application/excel'; $fext='xlsx'; }
    elsif ($att->{title_link} =~ /\.pptx$/)
    { $ft='application/powerpoint'; $fext='pptx'; }
    else
    {
      print STDERR "WARNING: no filetype given for attachment: \"", $att->{title_link} ,"\".\n";
    }
  }
  elsif ($ft eq 'image/gif')
  { $fext='gif'; }
  elsif ($ft eq 'image/jpeg')
  { $fext='jpg'; }
  elsif ($ft eq 'image/png')
  { $fext='png'; }
  elsif ($ft eq 'audio/mpeg')
  { $fext='mp3'; }
  elsif ($ft eq 'video/mp4')
  { $fext='mp4'; }
  elsif ($ft eq 'application/pdf')
  { $fext='pdf'; }
  else
  {
    print STDERR "WARNING (improve the code!): unknown file extension for file type: \"$ft\".\n";
  }

  # add file extension to the filename if necessary
  if ($fext and $fn !~ /\.$fext$/)
  {
    $fn .= "." . $fext;
  }

  # don't overwrite existing files
  if (-e "$downloadFolder/$fn")
  {
    my $fnNum = 1;
    while ( -e $downloadFolder ."/". $fnNum ."-". $fn )
    {
      $fnNum++;
    }
    $fn = $fnNum ."-". $fn;
  }

  # download and save attachment
  print STDERR "DEBUG: downloading attachment from URL: ", $att->{title_link}, "\n"  if ($self->debug);
  open (ATT, ">$downloadFolder/$fn") or do
  {
    die "ERROR: cannot save to file \"$downloadFolder/$fn\"";
  };

  print ATT $self->getFile( fileURL => $att->{title_link} );
  close ATT;

  return ($fn, $ft);
}

=item send(:$room,:$id,:$message)

NOT IMPLEMENTED YET

NEEDS TO BE UPDATED to the new API
The appropriate new API calls are most likely: chat.sendMessage or chat.postMessage

Sends a message to a room.

   $chat->send(room => "general", message => "Hello, world!");

=cut

method send(:$room,:$id,:$message) {
  die "ERROR: NOT IMPLEMENTED YET";

   if (not $id and not $room)
   {
     die "ERROR: send needs either id or roomname";
   }
   $id //= $self->get_room_id(room => "$room");
   $room //= $self->get_room_name(id => "$id");

#   my $msg = {
#      msg => $message,
#   };
#   $self->post($self->server . "/api/v1/rooms/$id/send", encode_json($msg));

#   if ($self->debug) {
#      print STDERR Dumper($self->response);
#   }
}

# looks up a room's internal id or fetches from the server if not previously done yet.
# Throws an exception if it's an invalid room name.
method get_room_id(:$room) {
  $self->getMyRoomsFull;        # update cache
  if (not exists $self->{rooms}{$room}) {
    die "ERROR: invalid_room";
  }
  return $self->{rooms}{$room}{id};
}

# looks up a room's name or fetches from the server if not previously done yet.
# Throws an exception if it's an invalid room id.
method get_room_name(:$id) {
  $self->getMyRoomsFull;        # update cache

  foreach my $rName (keys %{ $self->{rooms} })
  {
    if ($self->{rooms}{$rName}{id} eq $id)
    {
      return $rName;
    }
  }
  # else
  die "ERROR: invalid_id";
}

# looks up a room's type or fetches from the server if not previously done yet.
# Throws an exception if it's an invalid room name.
method get_room_type(:$room) {
  $self->getMyRoomsFull;        # update cache
  if (not exists $self->{rooms}{$room}) {
    die "ERROR: invalid_room";
  }
  return $self->{rooms}{$room}{type};
}

# convenience method that stuffs in some authentication headers into a GET request
method get($url) {
   $self->response($self->ua->get($url,"X-Auth-Token" => $self->authToken, "X-User-Id" => $self->userId));
   if ($self->response->is_error)
   {
     # are we too fast for the server?
     if ($self->response->status_line =~ /Too Many Requests/)
     {
       while ($self->response->status_line =~ /Too Many Requests/)
       {
         print STDERR "The server complains that we are too fast - waiting for 60 seconds...\n";
         sleep 60;
         # and try again
         $self->response($self->ua->get($url,"X-Auth-Token" => $self->authToken, "X-User-Id" => $self->userId));
       }
     }

     else
     {
       die "ERROR: http_error: ". $self->response->status_line;
     }
   }
}

# convenience method that stuffs in some authentication headers into a POST request
method post($url,$content) {
   $self->response($self->ua->post($url,"X-Auth-Token" => $self->authToken, "X-User-Id" => $self->userId, "Content-Type" => "application/json", Content => $content));
   if ($self->response->is_error)
   {
     # are we too fast for the server?
     if ($self->response->status_line =~ /Too Many Requests/)
     {
       while ($self->response->status_line =~ /Too Many Requests/)
       {
         print STDERR "The server complains that we are too fast - waiting for 60 seconds...\n";
         sleep 60;
         # and try again
         $self->response($self->ua->get($url,"X-Auth-Token" => $self->authToken, "X-User-Id" => $self->userId));
       }
     }

     else
     {
       die "ERROR: http_error: ". $self->response->status_line;
     }
   }
}

=back

=head1 AUTHORS

=over 4

=item 2016: Dale Evans, C<< <daleevans@github> >> L<http://devans.mycanadapayday.com>

=over 2

=item Initial version

=back

=back

=over 4

=item 2021: Andy Spiegl, C<< <a.spiegl+rocketchat@lmu.de> >>

=over 4

=item Adaptation to the new API

=item Extension with more methods for handling messages and attachments

=back

=back


=head1 REPOSITORY

L<https://github.com/daleevans/perl-Net-RocketChat>
L<https://github.com/raid1/perl-Net-RocketChat>


=head1 SEE ALSO

L<Developer Guide (REST API)|https://developer.rocket.chat/api/rest-api>

Dale Evans, C<< <daleevans@github> >> L<http://devans.mycanadapayday.com>

=head1 REPOSITORY

L<https://github.com/daleevans/perl-Net-RocketChat>

=head1 SEE ALSO

=cut

1;

