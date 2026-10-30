import 'package:belog/core/theme/app_palette.dart';
import 'package:flutter/material.dart';

class AppTheme {
  // --- Shared Border Styling ---
  static _border(
          {Color color = AppPalette.greyColorLight,
          double width = 1.5,
          double radius = 8.0}) =>
      OutlineInputBorder(
        borderSide: BorderSide(color: color, width: width),
        borderRadius: BorderRadius.circular(radius),
      );

  // --- Dark Theme ---
  static final darkThemeMode = ThemeData.dark().copyWith(
    brightness: Brightness.dark, // Explicitly set brightness to dark
    scaffoldBackgroundColor: AppPalette.blackColor, // Main dark background
    colorScheme: const ColorScheme.dark(
      // Define color scheme for dark mode
      primary: AppPalette.greenColor,
      secondary: AppPalette.greenColor,
      surface: AppPalette.blackColorLight, // For cards and surfaces
      onPrimary: AppPalette.whiteColor,
      onSecondary: AppPalette.whiteColor,
      onSurface: AppPalette.whiteColor,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppPalette.blackColor, // Dark AppBar background
      elevation: 0, // No shadow for AppBar
      titleTextStyle: TextStyle(
        // Style AppBar title text
        color: AppPalette.whiteColor,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
      iconTheme:
          IconThemeData(color: AppPalette.whiteColor), // White icons in AppBar
    ),
    textTheme: const TextTheme(
      // Define text theme for dark mode
      bodyMedium: TextStyle(color: AppPalette.whiteColor), // Default body text
      bodyLarge: TextStyle(color: AppPalette.whiteColor),
      bodySmall: TextStyle(color: AppPalette.greyColor), // Less prominent text
      titleLarge: TextStyle(
          color: AppPalette.whiteColor, fontWeight: FontWeight.bold), // Titles
      titleMedium:
          TextStyle(color: AppPalette.whiteColor, fontWeight: FontWeight.w500),
      titleSmall: TextStyle(
          color: AppPalette.greyColorLight), // Subtitles or smaller titles
      labelLarge: TextStyle(color: AppPalette.whiteColor), // Button text
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: AppPalette.blackColorLight, // Dark chip background
      labelStyle: TextStyle(color: AppPalette.whiteColor), // White chip label
      secondaryLabelStyle: TextStyle(color: AppPalette.whiteColor),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8))),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppPalette.greyColorDark, // Dark input field background
      contentPadding:
          const EdgeInsets.symmetric(vertical: 16.0, horizontal: 20.0),
      border: _border(color: AppPalette.greyColorLight), // Grey border
      enabledBorder: _border(color: AppPalette.greyColorLight),
      focusedBorder: _border(
          color: AppPalette.greenColor, width: 2.0), // Green focused border
      errorBorder: _border(color: AppPalette.errorColor),
      hintStyle:
          const TextStyle(color: AppPalette.greyColorLight), // Grey hint text
      labelStyle:
          const TextStyle(color: AppPalette.whiteColor), // White label text
      errorStyle: const TextStyle(color: AppPalette.errorColor),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      // Style for ElevatedButton - adjust as needed
      style: ElevatedButton.styleFrom(
        backgroundColor: AppPalette.greenColor, // Green button background
        foregroundColor: AppPalette.blackColor, // Dark text on button
        textStyle: const TextStyle(fontWeight: FontWeight.bold),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      // Style for TextButton - adjust as needed
      style: TextButton.styleFrom(
        foregroundColor: AppPalette.greenColor, // Green text for text buttons
        textStyle: const TextStyle(fontWeight: FontWeight.bold),
      ),
    ),
    iconTheme: const IconThemeData(
        color: AppPalette.whiteColor), // Default icon color - white
    primaryIconTheme: const IconThemeData(
        color: AppPalette.whiteColor), // Primary icon color - white
  );

  // --- Light Theme ---
  static final lightThemeMode = ThemeData.light().copyWith(
    brightness: Brightness.light, // Explicitly set brightness to light
    scaffoldBackgroundColor: AppPalette.lightBackground, // Light background
    colorScheme: const ColorScheme.light(
      // Define color scheme for light mode
      primary:
          AppPalette.gradient1, // Use gradient 1 as primary, adjust as needed
      secondary: AppPalette.gradient1,
      surface: AppPalette.lightGrey, // Light grey for surfaces
      onPrimary: AppPalette.whiteColor, // White text on primary (gradient)
      onSecondary: AppPalette.whiteColor, // Dark text on light background
      onSurface: AppPalette.lightBlack,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppPalette.lightBackground, // Light AppBar background
      elevation: 0,
      titleTextStyle: TextStyle(
        color: AppPalette.lightBlack,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
      iconTheme:
          IconThemeData(color: AppPalette.lightBlack), // Dark icons in AppBar
    ),
    textTheme: const TextTheme(
      // Define text theme for light mode
      bodyMedium:
          TextStyle(color: AppPalette.lightBlack), // Default body text - dark
      bodyLarge: TextStyle(color: AppPalette.lightBlack),
      bodySmall: TextStyle(
          color: AppPalette.lightGreyText), // Less prominent text - grey
      titleLarge: TextStyle(
          color: AppPalette.lightBlack,
          fontWeight: FontWeight.bold), // Titles - dark
      titleMedium:
          TextStyle(color: AppPalette.lightBlack, fontWeight: FontWeight.w500),
      titleSmall:
          TextStyle(color: AppPalette.lightGreyText), // Subtitles - grey
      labelLarge: TextStyle(color: AppPalette.lightBlack), // Button text - dark
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: AppPalette.lightGrey, // Light grey chip background
      labelStyle: TextStyle(color: AppPalette.lightBlack), // Dark chip label
      secondaryLabelStyle: TextStyle(color: AppPalette.lightBlack),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8))),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppPalette.lightBackground, // Light input field background
      contentPadding:
          const EdgeInsets.symmetric(vertical: 16.0, horizontal: 20.0),
      border: _border(color: AppPalette.lightBorder), // Light grey border
      enabledBorder: _border(color: AppPalette.lightBorder),
      focusedBorder: _border(
          color: AppPalette.gradient1, width: 2.0), // Gradient focused border
      errorBorder: _border(color: AppPalette.errorColor),
      hintStyle: const TextStyle(
          color: AppPalette.lightGreyText), // Light grey hint text
      labelStyle:
          const TextStyle(color: AppPalette.lightBlack), // Dark label text
      errorStyle: const TextStyle(color: AppPalette.errorColor),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppPalette.gradient1, // Gradient button background
        foregroundColor: AppPalette.whiteColor, // White text on button
        textStyle: const TextStyle(fontWeight: FontWeight.bold),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppPalette.gradient1, // Gradient text for text buttons
        textStyle: const TextStyle(fontWeight: FontWeight.bold),
      ),
    ),
    iconTheme: const IconThemeData(
        color: AppPalette.lightBlack), // Default icon color - dark
    primaryIconTheme: const IconThemeData(
        color: AppPalette.lightBlack), // Primary icon color - dark
  );
}
