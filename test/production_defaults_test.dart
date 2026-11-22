import 'package:flutter_test/flutter_test.dart';
import 'package:snad/core/app_links.dart';

void main() {
  test('ordinary builds include valid public production policy links', () {
    expect(AppLinks.support, 'https://jobsnad.com/support/');
    expect(AppLinks.privacy, 'https://jobsnad.com/privacy/');
    expect(AppLinks.hasSupport, isTrue);
    expect(AppLinks.hasPrivacy, isTrue);
    expect(
      AppLinks.jobShareUri('123').toString(),
      'https://jobsnad.com/jobs/123',
    );
  });
}
