// Example usage in a widget
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

class ResponsiveExample extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Initialize the responsive helper
    ResponsiveHelper.init(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Responsive Design', style: TextStyle(fontSize: 20.f)),
        toolbarHeight: 60.h,
      ),
      body: Padding(
        padding: EdgeInsets.all(16.sp),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Device info
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(12.sp),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8.sp),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Device: ${ResponsiveHelper.deviceType.name.toUpperCase()}',
                    style: TextStyle(
                      fontSize: 16.f,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    'Screen: ${ResponsiveHelper.screenWidth.toInt()} x ${ResponsiveHelper.screenHeight.toInt()}',
                    style: TextStyle(fontSize: 14.f),
                  ),
                ],
              ),
            ),

            SizedBox(height: 24.h),

            // Sample content
            Text(
              'Heading Text',
              style: TextStyle(fontSize: 24.f, fontWeight: FontWeight.bold),
            ),

            SizedBox(height: 16.h),

            Text(
              'This is body text that scales appropriately for different device types. The scaling is conservative to maintain readability.',
              style: TextStyle(fontSize: 16.f),
            ),

            SizedBox(height: 20.h),

            // Sample button
            Container(
              width: 200.w,
              height: 48.h,
              child: ElevatedButton(
                onPressed: () {},
                child: Text('Button', style: TextStyle(fontSize: 16.f)),
              ),
            ),

            SizedBox(height: 20.h),

            // Sample card
            Container(
              width: double.infinity,
              height: 120.h,
              padding: EdgeInsets.all(16.sp),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12.sp),
              ),
              child: Row(
                children: [
                  Icon(Icons.star, size: 24.ic, color: Colors.orange),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Card Title',
                          style: TextStyle(
                            fontSize: 18.f,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 4.h),
                        Text(
                          'Card description text',
                          style: TextStyle(fontSize: 14.f),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
