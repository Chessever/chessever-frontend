#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#
Pod::Spec.new do |s|
  s.name                  = 'file_picker'
  s.version               = '0.0.1'
  s.summary               = 'A flutter plugin to show native file picker dialogs'
  s.description           = <<-DESC
A flutter plugin to show native file picker dialogs.
                       DESC
  s.homepage              = 'https://github.com/miguelpruivo/plugins_flutter_file_picker'
  s.license               = { :file => '../LICENSE' }
  s.author                = 'Miguel Ruivo'
  s.source                = { :path => '.' }
  s.source_files          = 'file_picker/Sources/**/*.{m,h}'
  s.public_header_files   = 'file_picker/Sources/file_picker/include/**/*.h'
  s.module_map            = 'file_picker/Sources/file_picker/include/file_picker.modulemap'
  
  s.ios.deployment_target = '12.0'

  s.dependency 'Flutter'

  # PATCHED (see third_party/file_picker/PATCH.md): document picker only, to keep
  # the media/audio code paths (and DKImagePickerController) out of the binary.
  # Kept in lockstep with the same decision in file_picker/Package.swift so the
  # CocoaPods and SPM paths produce the same set of linked APIs.
  s.pod_target_xcconfig = { "GCC_PREPROCESSOR_DEFINITIONS" => "PICKER_DOCUMENT=1" }
  s.resource_bundles = {'file_picker_ios_privacy' => ['file_picker/Sources/file_picker/PrivacyInfo.xcprivacy']}

end
