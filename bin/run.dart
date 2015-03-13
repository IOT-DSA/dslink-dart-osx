import "dart:async";

import "package:osx/osx.dart";
import "package:dslink/http_client.dart";
import "package:dslink/responder.dart";
import "package:dslink/common.dart";
import "package:dslink/src/crypto/pk.dart";

main() async {
  var provider = new SimpleNodeProvider();

  provider.registerFunction("system.speak", (path, params) async {
    speak(params["text"]);
  });

  provider.registerFunction("applications.activate", (path, params) {
    Applications.activate(params["application"]);
  });

  provider.registerFunction("applications.quit", (path, params) {
    Applications.quit(params["application"]);
  });

  provider.registerFunction("applications.list", (path, params) {
    return new SimpleTableResult(Applications.list(normal: true).map((it) => {
      "name": it.name
    }).toList(), [
      {
        "name": "name",
        "type": "string"
      }
    ]);
  });

  provider.init({
    "System": {
      "Speak": {
        r"$invokable": "write",
        r"$function": "system.speak",
        r"$params": [
          {
            "name": "text",
            "type": "string"
          }
        ]
      },
      "Battery Level": {
        r"$type": "number",
        r"?value": Battery.getLevel()
      },
      "Plugged In": {
        r"$type": "bool",
        r"?value": Battery.isPluggedIn()
      },
      "Volume": {
        "Level": {
          r"$type": "number",
          "?value": AudioVolume.getVolume()
        },
        "Muted": {
          r"$type": "bool",
          "?value": AudioVolume.isMuted()
        }
      }
    },
    "Applications": {
      "Activate": {
        r"$invokable": "write",
        r"$function": "applications.activate",
        r"$params": [
          {
            "name": "application",
            "type": "string"
          }
        ]
      },
      "List": {
        r"$invokable": "read",
        r"$function": "applications.list",
        r"$columns": [
          {
            "name": "applications",
            "type": "tabledata"
          }
        ]
      },
      "Quit": {
        r"$invokable": "write",
        r"$function": "applications.quit",
        r"$params": [
          {
            "name": "application",
            "type": "string"
          }
        ]
      }
    }
  });

  new Timer.periodic(new Duration(seconds: 3), (t) {
    provider.getNode("/System/Battery Level").updateValue(Battery.getLevel());
    provider.getNode("/System/Volume/Level").updateValue(AudioVolume.getVolume());
    provider.getNode("/System/Volume/Muted").updateValue(AudioVolume.isMuted());
    provider.getNode("/System/Is Plugged In").updateValue(Battery.isPluggedIn());
  });

  var link = new HttpClientLink(
    "http://127.0.0.1:8080/conn",
    "osx-",
    new PrivateKey.generate(),
    isResponder: true,
    nodeProvider: provider
  );

  await link.connect();
  print("Connected");
}
