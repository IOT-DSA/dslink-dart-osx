import "dart:async";
import "dart:io";

import "package:osx/osx.dart";
import "package:dslink/client.dart";
import "package:dslink/responder.dart";
import "package:args/args.dart";

SimpleNodeProvider provider;

bool hasBattery = false;

main(List<String> argv) async {
  try {
    Battery.getLevel();
    hasBattery = true;
  } catch (e) {
  }

  var argp = new ArgParser();
  var args = argp.parse(argv);

  if (args.rest.length != 1) {
    print("Usage: dslink-osx [options] <url>");
    if (argp.usage.isNotEmpty) {
      print(argp.usage);
    }
    exit(1);
  }

  provider = new SimpleNodeProvider();

  provider.registerFunction("system.speak", (path, params) async {
    speak(params["text"], voice: params["voice"] == "Default Voice" ? null : params["voice"]);
  });

  provider.registerFunction("applications.activate", (path, params) {
    Applications.activate(params["application"]);
  });

  provider.registerFunction("applications.quit", (path, params) {
    Applications.quit(params["application"]);
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

  var initializer = {
    "System": {
      "Speak": {
        r"$invokable": "write",
        r"$function": "system.speak",
        r"$params": [
          {
            "name": "text",
            "type": "string"
          },
          {
            "name": "voice",
            "type": "string",
            "default": "Default Voice"
          }
        ]
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
        r"$type": "int",
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
      "Used Memory": {
        r"$type": "int",
        "?value": _availableMemory - getFreeMemory()
      },
      "Free Memory": {
        r"$type": "int",
        "?value": getFreeMemory()
      },
      "Total Memory": {
        r"$type": "int",
        "?value": _availableMemory
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
  };

  if (hasBattery) {
    initializer["System"]["Battery Level"] = {
      r"$type": "number",
      r"?value": Battery.getLevel()
    };
  }

  loadExtensions(initializer);

  provider.init(initializer);

  new Timer.periodic(new Duration(seconds: 3), (t) {
    if (hasBattery) {
      provider.getNode("/System/Battery Level").updateValue(Battery.getLevel());
    }

    provider.getNode("/System/Volume/Level").updateValue(AudioVolume.getVolume());
    provider.getNode("/System/Volume/Muted").updateValue(AudioVolume.isMuted());
    var freemem = getFreeMemory();
    provider.getNode("/System/Free Memory").updateValue(freemem);
    provider.getNode("/System/Used Memory").updateValue(_availableMemory - freemem);
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
    args.rest[0],
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

  return mem;
}

int _availableMemory = SystemInformation.getPhysicalMemory();

void loadExtensions(Map i) {
  Map app(String name) {
    if (!Applications.isInstalled(name)) {
      return {
        "Application Name": {
          "?value": name
        }
      };
    }

    var id = name.toLowerCase().replaceAll(" ", "_");

    provider.registerFunction("${id}.close", (path, params) {
      Applications.quit(name);
    });

    provider.registerFunction("${id}.activate", (path, params) {
      Applications.activate(name);
    });

    return i[name] = {
      "Activate": {
        r"$function": "${id}.activate",
        r"$invokable": "write"
      },
      "Quit": {
        r"$function": "${id}.activate",
        r"$invokable": "write"
      },
      "Application Name": {
        r"$type": "string",
        "?value": name
      }
    };
  }

  void action(map, String name, dynamic handler(Map<String, dynamic> params), [List<Map<String, dynamic>> params]) {
    var appName = map["Application Name"]["?value"];
    var id = appName.toLowerCase().replaceAll(" ", "_");
    map[name] = {
      r"$function": id,
      r"$invokable": "write"
    };

    if (params != null) {
      map[name][r"$params"] = params;
    }
  }

  var launchpad = app("Launchpad");
  var missionControl = app("Mission Control");
  var textual = app("Textual 5");
  var atom = app("Atom");
  var finder = app("Finder");
  var activityMonitor = app("Activity Monitor");

  action(atom, "Create Document", (params) {
    Atom.createDocument();
  });

  action(finder, "Open File", (params) {
    Finder.open(params["file"]);
  }, [
    {
      "name": "file",
      "type": "string"
    }
  ]);
}
