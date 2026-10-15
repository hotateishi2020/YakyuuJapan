import 'package:flutter/material.dart';
import '../logic/display_settings.dart';

class DisplaySettingsPage extends StatelessWidget {
  const DisplaySettingsPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('表示設定')),
        body: ValueListenableBuilder<Set<String>>(
          valueListenable: DisplaySettings.instance,
          builder: (context, _, child) => ListView(children: [
            const Padding(
                padding: EdgeInsets.all(16),
                child: Text('選手マークの表示\n設定はこのブラウザに保存されます。')),
            for (final item in playerMarkDescriptions.entries)
              SwitchListTile(
                  title: Text('${item.value.$1}  ${item.value.$2}'),
                  value: DisplaySettings.instance.shows(item.key),
                  onChanged: (shown) =>
                      DisplaySettings.instance.setShown(item.key, shown)),
          ]),
        ),
      );
}
