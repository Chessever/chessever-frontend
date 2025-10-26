
import 'package:purchases_flutter/models/package_wrapper.dart';

String getTitleBySubscriptionTye(PackageType type){
  if(type == PackageType.annual){
    return "Yearly";
  }
  if(type == PackageType.monthly){
    return "Monthly";
  }
  return type.name;
}