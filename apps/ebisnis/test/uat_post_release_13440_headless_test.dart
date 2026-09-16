// Fast rehearsal of the same acceptance flow before a native Windows run.
import '../integration_test/uat_post_release_13440_test.dart' as uat;

void main() => uat.main(headless: true);
