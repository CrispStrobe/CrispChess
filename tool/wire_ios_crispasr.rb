#!/usr/bin/env ruby
# Wire ios/Frameworks/crispasr.xcframework into the Runner target: linked,
# and embedded with CodeSignOnCopy, so the app ships
# Frameworks/crispasr.framework and Dart FFI opens it as
# `crispasr.framework/crispasr`. Adapted from CrisperWeaver's
# scripts/wire_ios_xcframework.rb (same arrangement, same App Store path).
#
# Idempotent. Run by tool/ios_crispasr.sh in CI; the wiring is not committed,
# so a checkout without the framework still builds (voice moves stay hidden).

require 'xcodeproj'

ROOT      = File.expand_path('..', __dir__)
PROJECT   = File.join(ROOT, 'ios', 'Runner.xcodeproj')
XCFW_PATH = 'Frameworks/crispasr.xcframework'

abort "missing ios/#{XCFW_PATH} — run tool/ios_crispasr.sh" \
  unless File.exist?(File.join(ROOT, 'ios', XCFW_PATH))

project = Xcodeproj::Project.open(PROJECT)
target  = project.targets.find { |t| t.name == 'Runner' } or abort 'Runner target not found'

group = project.main_group['Frameworks'] || project.main_group.new_group('Frameworks')
ref = group.files.find { |f| f.path == XCFW_PATH }
unless ref
  ref = group.new_file(XCFW_PATH)
  ref.last_known_file_type = 'wrapper.xcframework'
end

link = target.frameworks_build_phase
link.add_file_reference(ref) unless link.files_references.include?(ref)

# Copy Files phase into <app>.app/Frameworks (dst_subfolder_spec 10).
embed = target.copy_files_build_phases.find { |p| p.dst_subfolder_spec == '10' && p.name&.include?('Embed') }
unless embed
  embed = target.new_copy_files_build_phase('Embed Frameworks')
  embed.dst_subfolder_spec = '10'
  embed.dst_path = ''
end
file = embed.files.find { |bf| bf.file_ref == ref } || embed.add_file_reference(ref)
file.settings = { 'ATTRIBUTES' => %w[CodeSignOnCopy RemoveHeadersOnCopy] }

target.build_configurations.each do |config|
  paths = config.build_settings['FRAMEWORK_SEARCH_PATHS']
  paths = paths.nil? ? ['$(inherited)'] : Array(paths)
  config.build_settings['FRAMEWORK_SEARCH_PATHS'] = paths | ['$(PROJECT_DIR)/Frameworks']
  # Xcode 15+ sandboxes build scripts, and Flutter's scripts then cannot
  # touch the embedded framework (CrisperWeaver needed the same).
  config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
end

project.save
puts 'wired crispasr.xcframework into Runner (linked, embedded with CodeSignOnCopy)'
