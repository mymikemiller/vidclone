import 'dart:async';
import 'dart:io' show Platform;

import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:googleapis/youtube/v3.dart';

// The API Key obtained from the Google Developers Console.
final apiKey = getEnvVar('GOOGLE_API_KEY');

// We use 50, Youtube's max for this value.
final maxApiResultsPerCall = 50;

// The maximum number of videos returned by the api before yeilding the earliest in the window.
// This is necessary because videos are returned out of order. We're specifying
// here that we can expect any set videos this size returned consecutively by
// the api to include the youngest video of any videos that have yet to be returned.
final slidingWindowSize = 30;

String getEnvVar(String key) {
  final value = Platform.environment[key];
  if (value == null) {
    throw 'Environment variable not set: $key';
  }
  return value;
}

class Video {
  final String title;
  final String description;
  final String url;
  final DateTime date;

  Video(this.title, this.description, this.url, this.date);

  @override
  String toString() {
    return '$date $url: $title';
  }
}

Stream<Video> allUploads(YoutubeApi api, String channelId) async* {
  final channels =
      await api.channels.list('contentDetails, snippet', id: channelId);

  if (channels.items.isEmpty) {
    throw 'Channel not found for id ${channelId}';
  } else if (channels.items.length > 1) {
    throw 'Too many channels found for id ${channelId}';
  }

  final channel = channels.items[0];
  final channelDescription = channel.snippet.description;
  final uploadsPlaylistId = channel.contentDetails.relatedPlaylists.uploads;
  var nextPageToken; // Null means we haven't started, '' means we're done
  var playlistItems;
  var slidingWindow = List<Video>();

  while (nextPageToken == null || nextPageToken.isNotEmpty) {
    playlistItems = await api.playlistItems.list('contentDetails, snippet',
        playlistId: uploadsPlaylistId,
        pageToken: nextPageToken,
        maxResults: maxApiResultsPerCall);

    nextPageToken = playlistItems.nextPageToken;

    // Add the videos in this page one by one to the sliding window, keeping
    // them in date order, picking off from the sliding window when it gets too full
    for (var playlistItem in playlistItems.items) {
      final video = Video(
        playlistItem.snippet.title,
        playlistItem.snippet.description,
        'https://www.youtube.com/watch?v=${playlistItem.snippet.resourceId.videoId}',
        playlistItem.snippet.publishedAt,
      );

      // Find the first video that has a date more recent than this video and add it right before
      var i;
      for (i = 0; i < slidingWindow.length; i++) {
        if (video.date.compareTo(slidingWindow[i].date) < 0) {
          break;
        }
      }

      slidingWindow.insert(i, video);
      if (slidingWindow.length > slidingWindowSize) {
        // Yield the most recent video in the sliding window
        yield slidingWindow.removeLast();
      }
    }
  }

  // Yield the remaining items in the window
  for (var video in slidingWindow) {
    yield video;
  }
}

void main(List<String> arguments) async {
  final client = auth.clientViaApiKey(apiKey);
  final api = YoutubeApi(client);
  await for (var video in allUploads(api, 'UC9CuvdOVfMPvKCiwdGKL3cQ')) {
    print(video);
  }
}
