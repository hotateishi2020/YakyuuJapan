import 'package:flutter/material.dart';
import '../config/org_config.dart';

class Headers {
  static Widget globalHeader(
    double h,
    Color color,
    String title,
    double padding_vertical,
    double padding_horizontal, {
    OrgKind? orgKind,
    ValueChanged<OrgKind>? onOrgChanged,
  }) {
    return Container(
      height: h,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFFE10600), Color(0xFFFF9800)],
        ),
      ),
      padding: EdgeInsets.symmetric(horizontal: padding_horizontal, vertical: padding_vertical),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Image.asset(
                'backend/assets/images/logo_yakyuu_japan.png',
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
                semanticLabel: title,
              ),
            ),
          ),
          if (orgKind != null && onOrgChanged != null) _orgPicker(orgKind, onOrgChanged),
        ],
      ),
    );
  }

  static Widget _orgPicker(OrgKind selected, ValueChanged<OrgKind> onChanged) {
    return Material(
      color: Colors.black,
      borderRadius: BorderRadius.circular(4),
      child: PopupMenuButton<OrgKind>(
        padding: EdgeInsets.zero,
        tooltip: '競技団体',
        initialValue: selected,
        position: PopupMenuPosition.under,
        color: Colors.black,
        onSelected: onChanged,
        itemBuilder: (context) => [
          for (final kind in OrgKind.values)
            PopupMenuItem(
              value: kind,
              child: Center(
                child: Text(
                  OrgConfig.of(kind).label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
        child: SizedBox(
          height: hOfPicker,
          width: 72,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                OrgConfig.of(selected).label,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const Positioned(
                right: 2,
                child: Icon(Icons.arrow_drop_down, size: 18, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const hOfPicker = 28.0;
}
