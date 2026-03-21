import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/assets/app_assets.dart';

class UpSnapLogo extends StatelessWidget {
  const UpSnapLogo({super.key, this.size = 88});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(AppAssets.gopher, width: size, height: size);
  }
}
