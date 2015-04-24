import "dart:async";
import "dart:io";

import "package:osx/osx.dart";
import "package:dslink/client.dart";
import "package:dslink/responder.dart";

const Duration defaultTick = const Duration(seconds: 3);

LinkProvider link;
SimpleNodeProvider provider;

bool hasBattery = false;

class ActivateApplicationNode extends SimpleNode {
  String app;

  ActivateApplicationNode(String path, [this.app]) : super(path);

  @override
  Object onInvoke(Map params) {
    if (getConfig(r"$application") != null) {
      app = getConfig(r"$application");
    }

    var c = app == null ? params["application"] : app;

    if (c == null) {
      return [];
    }

    Applications.activate(c);
    return [];
  }
}

class QuitApplicationNode extends SimpleNode {
  String app;

  QuitApplicationNode(String path, [this.app]) : super(path);

  @override
  Object onInvoke(Map params) {
    if (getConfig(r"$application") != null) {
      app = getConfig(r"$application");
    }

    var c = app == null ? params["application"] : app;

    if (c == null) {
      return [];
    }

    Applications.quit(c);
    return [];
  }
}

class UpdateLocationNode extends SimpleNode {
  UpdateLocationNode(String path) : super(path);

  @override
  Object onInvoke(Map params) {
    Geolocation.getLocation().then((info) {
      provider.getNode("/Location/Latitude").updateValue(info.latitude);
      provider.getNode("/Location/Longitude").updateValue(info.longitude);
      provider.getNode("/Location/Accuracy").updateValue(info.accuracy);
      provider.getNode("/Location/Timestamp").updateValue(info.timestamp);
    });
    return [];
  }
}

class SpeakNode extends SimpleNode {
  SpeakNode(String path) : super(path);

  @override
  Object onInvoke(Map params) {
    speak(params["text"], voice: params["voice"] == "Default Voice" ? null : params["voice"]);
    return [];
  }
}

class OpenedAppsNode extends SimpleNode {
  OpenedAppsNode(String path) : super(path);

  @override
  Object onInvoke(Map params) {
    return new SimpleTableResult(TaskManager.getOpenTasks().map((it) => {
      "name": it
    }).toList(), [
      {
        "name": "name",
        "type": "string"
      }
    ]);
  }
}

class ConfigureTickNode extends SimpleNode {
  ConfigureTickNode(String path) : super(path);

  @override
  Object onInvoke(Map params) {
    if (params["seconds"] != null) {
      tick = new Duration(seconds: params["seconds"]);
      ticker();
    }
    return [];
  }
}

class AppsNode extends SimpleNode {
  AppsNode(String path) : super(path);

  @override
  Object onInvoke(Map params) {
    return new SimpleTableResult(Applications.list().map((it) => {
      "name": it.name
    }).toList(), [
      {
        "name": "name",
        "type": "string"
      }
    ]);
  }
}

main(List<String> args) async {
  try {
    Battery.getLevel();
    hasBattery = true;
  } catch (e) {
  }

  var initializer = {
    "Configure Tick": {
      r"$invokable": "write",
      r"$is": "configureTick",
      r"$params": [
        {
          "name": "seconds",
          "type": "int",
          "default": tick.inSeconds
        }
      ]
    },
    "System": {
      "Speak": {
        r"$invokable": "write",
        r"$is": "speak",
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
        "?value": _availableMemory - getFreeMemory(),
        r"$min": 0,
        r"$max": _availableMemory
      },
      "Free Memory": {
        r"$type": "int",
        "?value": getFreeMemory(),
        r"$min": 0,
        r"$max": _availableMemory
      },
      "Total Memory": {
        r"$type": "int",
        "?value": _availableMemory
      }
    },
    "Applications": {
      "Activate": {
        r"$invokable": "write",
        r"$is": "activate",
        r"$params": [
          {
            "name": "application",
            "type": "string"
          }
        ],
        r"$result": "values"
      },
      "List": {
        r"$invokable": "read",
        r"$is": "applications",
        r"$columns": [
          {
            "name": "applications",
            "type": "tabledata"
          }
        ],
        r"$result": "table"
      },
      "Get Open": {
        r"$invokable": "read",
        r"$is": "opened",
        r"$columns": [
          {
            "name": "applications",
            "type": "tabledata"
          }
        ],
        r"$result": "table"
      },
      "Quit": {
        r"$invokable": "write",
        r"$is": "quit",
        r"$params": [
          {
            "name": "application",
            "type": "string"
          }
        ]
      }
    },
    "Location": {
      "Update": {
        r"$invokable": "write",
        r"$is": "updateLocation",
        r"$result": "values"
      },
      "Latitude": {
        r"$type": "number"
      },
      "Longitude": {
        r"$type": "number"
      },
      "Accuracy": {
        r"$type": "number"
      },
      "Timestamp": {
        r"$type": "string"
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

  Map<String, Function> profiles = {
    "activate": (String path) => new ActivateApplicationNode(path),
    "quit": (String path) => new QuitApplicationNode(path),
    "applications": (String path) => new AppsNode(path),
    "opened": (String path) => new OpenedAppsNode(path),
    "configureTick": (String path) => new ConfigureTickNode(path),
    "speak": (String path) => new SpeakNode(path),
    "updateLocation": (String path) => new UpdateLocationNode(path)
  };

  provider = new SimpleNodeProvider(initializer, profiles);

  (provider.getNode("/Location/Update") as SimpleNode).onInvoke({});

  ticker();

  provider.getNode("/System/Volume/Level").subscribe((update) {
    AudioVolume.setVolume(update.value);
  });

  provider.getNode("/System/Volume/Muted").subscribe((update) {
    AudioVolume.setMuted(update.value);
  });

  link = new LinkProvider(args, "MacOSX-", command: "osx-link", nodeProvider: provider);

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

Timer timer;
Duration tick = defaultTick;

ticker() {
  if (timer != null && timer.isActive) {
    timer.cancel();
    timer = null;
  }

  timer = new Timer.periodic(tick, (_) async {
    await sync();
  });
}

sync() async {
  if (hasBattery) {
    provider.getNode("/System/Battery Level").updateValue(Battery.getLevel());
  }

  provider.getNode("/System/Volume/Level").updateValue(AudioVolume.getVolume());
  provider.getNode("/System/Volume/Muted").updateValue(AudioVolume.isMuted());
  var freemem = getFreeMemory();
  provider.getNode("/System/Free Memory").updateValue(freemem);
  provider.getNode("/System/Used Memory").updateValue(_availableMemory - freemem);
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

    return i[name] = {
      "Activate": {
        r"$is": "activate",
        r"$invokable": "write",
        r"$application": name
      },
      "Quit": {
        r"$is": "quit",
        r"$invokable": "write",
        r"$application": name
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
