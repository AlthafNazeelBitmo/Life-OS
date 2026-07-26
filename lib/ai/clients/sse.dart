import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Turns a streamed HTTP response into server-sent-event payloads.
///
/// Written by hand rather than pulled from a package because all three
/// streaming providers use the same wire format with different envelopes, and
/// the whole job is "split on blank lines, strip the `data:` prefix".
Stream<String> sseEvents(http.StreamedResponse response) async* {
  var buffer = '';
  await for (final chunk
      in response.stream.transform(const Utf8Decoder(allowMalformed: true))) {
    buffer += chunk;

    // Events are separated by a blank line; anything after the last separator
    // is a partial event and stays in the buffer.
    while (true) {
      final boundary = buffer.indexOf('\n\n');
      if (boundary < 0) break;
      final rawEvent = buffer.substring(0, boundary);
      buffer = buffer.substring(boundary + 2);

      for (final line in rawEvent.split('\n')) {
        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload.isEmpty || payload == '[DONE]') continue;
        yield payload;
      }
    }
  }
}
