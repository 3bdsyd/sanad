import 'package:flutter/widgets.dart';
import '../domain/job_geography.dart';

class CountryFlag extends StatelessWidget {
  const CountryFlag({super.key, required this.country, this.size = 24});
  final JobCountry country;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Image.asset(
        country.flagAsset ?? 'flags/png/${country.code.toLowerCase()}.png',
        package: country.flagAsset == null ? 'flutter_multi_formatter' : null,
        width: size * 1.5,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, error, stack) =>
            Text(country.code, style: TextStyle(fontSize: size * .65)),
      ),
    ),
  );
}
