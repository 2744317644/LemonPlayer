platform :ios, '26.0'

# MobileVLCKit 3.7.x：LGPL、内置 libass（ASS/SSA 特效渲染）、MKV/HEVC/AV1/DTS 全格式
# 见 docs/tech/PLAYER_KERNEL.md（ADR-003）
target 'LemonPlayer' do
  use_frameworks!

  pod 'MobileVLCKit', '~> 3.7'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '26.0'
    end
  end
end
