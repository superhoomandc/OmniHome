import 'package:flutter/material.dart';

class NavBar extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onTap;

  const NavBar({
    super.key,
    required this.selectedIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.timer),
          label: 'Set Relay Timer',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.wifi),
          label: 'WiFi Settings',
        ),
      ],
      currentIndex: selectedIndex,
      selectedItemColor: const Color.fromARGB(255, 151, 9, 169),
      onTap: onTap,
    );
  }
}
