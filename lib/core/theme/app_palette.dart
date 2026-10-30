import 'package:flutter/material.dart';

class AppPalette {
  // ** Spotify Inspired Dark Theme Colors **
  static const Color blackColor =
      Color(0xFF121212); // Spotify's main dark background
  static const Color greyColorDark =
      Color(0xFF181818); // Slightly lighter dark grey
  static const Color greenColor = Color(0xFF1DB954); // Spotify's vibrant green
  static const Color whiteColor =
      Colors.white; // White for text and icons in dark mode
  static const Color greyColor =
      Color(0xFFB3B3B3); // Medium grey for less important text
  static const Color greyColorLight =
      Color(0xFF9A9A9A); // Lighter grey for hints, etc.
  static const Color blackColorLight =
      Color(0xFF282828); // Even lighter dark grey for cards/elements

  // ** Light Theme Colors (Inspired but may need adjustments) **
  static const Color lightBackground =
      Colors.white; // Light mode background - white
  static const Color lightGrey =
      Color(0xFFF4F4F4); // Light grey background for sections
  static const Color lightBlack =
      Colors.black87; // Dark text for light mode - near black
  static const Color lightGreyText =
      Color(0xFF666666); // Medium grey for less important text in light mode
  static const Color lightBorder = Color(0xFFE0E0E0); // Light border color

  // ** General App Colors (Can be used in both themes) **
  static const Color gradient1 = Color.fromRGBO(
      29, 185, 84, 1); // Spotify Green (same as greenColor for consistency)
  static const Color gradient2 = Color.fromRGBO(
      173, 232, 182, 1); // Lighter Greenish gradient (adjust if needed)
  static const Color errorColor = Colors.redAccent;
  static const Color transparentColor = Colors.transparent;
}
