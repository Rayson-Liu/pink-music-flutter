import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// 封面图片（带缓存与圆角）
class CoverImage extends StatelessWidget {
  final String url;
  final double size;
  final double radius;

  const CoverImage({
    super.key,
    required this.url,
    this.size = 48,
    this.radius = 10,
  });

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(Icons.music_note, color: Colors.white24, size: size * 0.4),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: url.isEmpty
          ? placeholder
          : CachedNetworkImage(
              imageUrl: url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              placeholder: (context, url) => placeholder,
              errorWidget: (context, url, error) => placeholder,
            ),
    );
  }
}
