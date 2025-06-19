// import 'package:flutter/material.dart';
// import '../widgets/status_bar.dart';
// import '../widgets/blur_background.dart';

// class InputDesignScreen extends StatefulWidget {
//   const InputDesignScreen({Key? key}) : super(key: key);

//   @override
//   State<InputDesignScreen> createState() => _InputDesignScreenState();
// }

// class _InputDesignScreenState extends State<InputDesignScreen> {
//   @override
//   void initState() {
//     super.initState();
//     Future.delayed(const Duration(seconds: 2), () {
//       if (mounted) {
//         Navigator.of(context).pushReplacementNamed('/splash_auth');
//       }
//     });
//   }

//   @override
//   Widget build(BuildContext context) {
//     final screenSize = MediaQuery.of(context).size;
//     final double aspectRatio = 393 / 852;
//     final double phoneWidth = screenSize.width < 500 ? screenSize.width : 393;
//     final double phoneHeight = phoneWidth / aspectRatio;

//     return Scaffold(
//       backgroundColor: const Color(0xFF0A0A0A),
//       body: Center(
//         child: AspectRatio(
//           aspectRatio: aspectRatio,
//           child: Container(
//             width: phoneWidth,
//             height: phoneHeight,
//             decoration: BoxDecoration(
//               color: const Color(0xFF0A0A0A),
//               borderRadius: BorderRadius.circular(32),
//               boxShadow: [
//                 BoxShadow(
//                   color: Colors.black.withOpacity(0.3),
//                   blurRadius: 24,
//                   offset: const Offset(0, 8),
//                 ),
//               ],
//             ),
//             child: Stack(
//               children: [
//                 const BlurBackground(),
//                 const Positioned(
//                   top: 0,
//                   left: 0,
//                   right: 0,
//                   child: StatusBar(),
//                 ),
//                 Center(
//                   child: Image.network(
//                     'https://cdn.builder.io/api/v1/image/assets/TEMP/73af920bddf3b3b86a27c37e991ed537b65ee271?placeholderIfAbsent=true',
//                     width: screenSize.width > 768 ? 120 : 80,
//                     height: screenSize.width > 768 ? 120 : 80,
//                     fit: BoxFit.contain,
//                   ),
//                 ),
//                 Positioned(
//                   bottom: 18,
//                   left: 0,
//                   right: 0,
//                   child: Center(
//                     child: Container(
//                       width: 134,
//                       height: 5,
//                       decoration: BoxDecoration(
//                         color: Colors.white,
//                         borderRadius: BorderRadius.circular(100),
//                       ),
//                     ),
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }
