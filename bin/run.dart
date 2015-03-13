import "dart:async";
import "dart:io";

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

  provider.registerFunction("applications.open", (path, params) {
    Opener.open(params["path"]);
  });

  provider.registerFunction("applications.opened", (path, params) {
    return new SimpleTableResult(TaskManager.getOpenTasks().map((it) => {
      "name": it
    }).toList(), [
      {
        "name": "name",
        "type": "string"
      }
    ]);
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
          r"$writable": "write",
          "?value": AudioVolume.getVolume()
        },
        "Muted": {
          r"$type": "bool",
          "?value": AudioVolume.isMuted(),
          r"$writable": "write"
        }
      },
      "Version": {
        r"$type": "string",
        "?value": SystemInformation.getVersion()
      },
      "Computer Name": {
        r"$type": "string",
        "?value": SystemInformation.getComputerName()
      },
      "CPU Speed": {
        "?value": SystemInformation.getCpuSpeed()
      },
      "CPU Type": {
         r"$type": "string",
        "?value": SystemInformation.getCpuType()
      },
      "Hostname": {
        r"$type": "string",
        "?value": SystemInformation.getHostName()
      },
      "Home Directory": {
        r"$type": "string",
        "?value": SystemInformation.getHomeDirectory()
      },
      "User": {
        r"$type": "string",
        "?value": SystemInformation.getUser()
      },
      "User Name": {
        r"$type": "string",
        "?value": SystemInformation.getUserName()
      },
      "Boot Volume": {
        r"$type": "string",
        "?value": SystemInformation.getBootVolume()
      },
      "Free Memory": {
        r"$type": "int",
        "?value": getFreeMemory()
      },
      "Used Memory": {
        r"$type": "number",
        "?value": _availableMemory - getFreeMemory()
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
      "Get Open": {
        r"$invokable": "read",
        r"$function": "applications.opened",
        r"$columns": [
          {
            "name": "applications",
            "type": "tabledata"
          }
        ]
      },
      "Open File": {
        r"$invokable": "read",
        r"$function": "applications.open",
        r"$params": [
          {
            "name": "path",
            "type": "string"
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
    var memfree = getFreeMemory();
    provider.getNode("/System/Free Memory").updateValue(memfree);
    provider.getNode("/System/Used Memory").updateValue(_availableMemory - memfree);
  });

  provider.getNode("/System/Volume/Level").valueStream.listen((x) {
    AudioVolume.setVolume(x.value);
  });

  provider.getNode("/System/Volume/Muted").valueStream.listen((x) {
    AudioVolume.setMuted(x.value);
  });

  var keyFile = new File("${Platform.environment["HOME"]}/Library/DSLinks/OSX/key.pem");

  if (!(await keyFile.exists())) {
    await keyFile.create(recursive: true);
    await keyFile.writeAsString(new PrivateKey.generate().saveToString());
  }

  var link = new HttpClientLink(
    "http://127.0.0.1:8080/conn",
    "osx-",
    new PrivateKey.loadFromString(await keyFile.readAsString()),
    isResponder: true,
    nodeProvider: provider
  );

  await link.connect();
  print("Connected");
}

int getFreeMemory() {
  var out = Process.runSync("vm_stat", [])
  .stdout
  .split("\n")
  .map((it) => it.trim())
  .firstWhere((it) => it.startsWith("Pages free:"))
  .split(":")
  .last
  .trim();
  out = out.substring(0, out.length - 1);

  var mem = (int.parse(out) * 4096) ~/ 1048576;

  return mem * 1000000;
}

int _availableMemory = SystemInformation.getPhysicalMemory() * 1000000;
