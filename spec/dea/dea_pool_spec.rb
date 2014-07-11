require "spec_helper"

module VCAP::CloudController
  describe VCAP::CloudController::DeaPool do
    let(:message_bus) { CfMessageBus::MockMessageBus.new }
    subject { DeaPool.new(message_bus) }

    describe "#register_subscriptions" do
      let(:dea_advertise_msg) do
        {
          "id" => "dea-id",
          "stacks" => ["stack"],
          "available_memory" => 1024,
          "app_id_to_count" => {}
        }
      end

      let(:dea_shutdown_msg) do
        {
          "id" => "dea-id",
          "ip" => "123.123.123.123",
          "version" => "1.2.3",
          "app_id_to_count" => {}
        }
      end

      it "finds advertised dea" do
        subject.register_subscriptions
        message_bus.publish("dea.advertise", dea_advertise_msg)
        subject.find_dea(mem: 1, stack: "stack", app_id: "app-id").should == "dea-id"
      end

      it "clears advertisements of DEAs being shut down" do
        subject.register_subscriptions
        message_bus.publish("dea.advertise", dea_advertise_msg)
        message_bus.publish("dea.shutdown", dea_shutdown_msg)

        subject.find_dea(mem: 1, stack: "stack", app_id: "app-id").should be_nil
      end
    end

    describe "#find_dea" do
      let(:dea_advertise_msg) do
        {
          "id" => "dea-id",
          "stacks" => ["stack"],
          "available_memory" => 1024,
          "available_disk" => available_disk,
          "app_id_to_count" => {
            "other-app-id" => 1
          }
        }
      end

      def dea_advertisement(options)
        dea_advertisement = {
          "id" => options[:dea],
          "stacks" => ["stack"],
          "available_memory" => options[:memory],
          "available_disk" => available_disk,
          "app_id_to_count" => {
            "app-id" => options[:instance_count]
          }
        }
        if options[:zone]
          dea_advertisement["placement_properties"] = {"zone" => options[:zone]}
        end
        if options[:dea_features]
          dea_advertisement["dea_features"] = options[:dea_features]
        end
        dea_advertisement
      end

      let(:dea_in_default_zone_with_1_instance_and_128m_memory) do
        dea_advertisement :dea => "dea-id1", :memory => 128, :instance_count => 1
      end

      let(:dea_in_default_zone_with_2_instances_and_128m_memory) do
        dea_advertisement :dea => "dea-id2", :memory => 128, :instance_count => 2
      end

      let(:dea_in_default_zone_with_1_instance_and_512m_memory) do
        dea_advertisement :dea => "dea-id3", :memory => 512, :instance_count => 1
      end

      let(:dea_in_default_zone_with_2_instances_and_512m_memory) do
        dea_advertisement :dea => "dea-id4", :memory => 512, :instance_count => 2
      end

      let(:dea_in_user_defined_zone_with_3_instances_and_1024m_memory) do
        dea_advertisement :dea => "dea-id5", :memory => 1024, :instance_count => 3, :zone => "zone1"
      end

      let(:dea_in_user_defined_zone_with_2_instances_and_1024m_memory) do
        dea_advertisement :dea => "dea-id6", :memory => 1024, :instance_count => 2, :zone => "zone1"
      end

      let(:dea_in_user_defined_zone_with_1_instance_and_512m_memory) do
        dea_advertisement :dea => "dea-id7", :memory => 512, :instance_count => 2, :zone => "zone1"
      end

      let(:dea_in_user_defined_zone_with_1_instance_and_256m_memory) do
        dea_advertisement :dea => "dea-id8", :memory => 256, :instance_count => 1, :zone => "zone1"
      end

      let(:dea_with_ssd_and_security) do
        dea_advertisement :dea => "dea-id-9", :memory => 1024, :instance_count => 2,
                          :dea_features => {"ssd" => true, "security" => true}
      end

      let(:dea_with_ssd_but_no_security) do
        dea_advertisement :dea => "dea-id-10", :memory => 1024, :instance_count => 2,
                          :dea_features => {"ssd" => true, "security" => false}
      end

      let(:dea_with_ssd_but_no_security_1_instance) do
        dea_advertisement :dea => "dea-id-11", :memory => 1024, :instance_count => 1,
                          :dea_features => {"ssd" => true, "security" => false}, :zone => "zone-1"
      end

      let(:dea_with_ssd_but_no_security_2_instance) do
        dea_advertisement :dea => "dea-id-12", :memory => 1024, :instance_count => 2,
                          :dea_features => {"ssd" => true, "security" => false}, :zone => "zone-1"
      end

      let(:dea_with_ssd_no_security_and_no_ha) do
        dea_advertisement :dea => "dea-id-13", :memory => 1024, :instance_count => 2,
                          :dea_features => {"ssd" => true, "security" => false, "ha" => false}, :zone => "zone-1"
      end

      let(:available_disk) { 100 }

      describe "dea availability" do
        it "only finds registered deas" do
          expect {
            subject.process_advertise_message(dea_advertise_msg)
          }.to change { subject.find_dea(mem: 1, stack: "stack", app_id: "app-id") }.from(nil).to("dea-id")
        end
      end

      describe "#only_in_zone_with_fewest_instances" do
        context "when all the DEAs are in the same zone" do
          it "finds the DEA within the default zone" do
            subject.process_advertise_message(dea_in_default_zone_with_1_instance_and_128m_memory)
            subject.process_advertise_message(dea_in_default_zone_with_2_instances_and_512m_memory)
            subject.find_dea(mem: 1, stack: "stack", app_id: "app-id").should == "dea-id1"
          end

          it "finds the DEA with enough memory within the default zone" do
            subject.process_advertise_message(dea_in_default_zone_with_1_instance_and_128m_memory)
            subject.process_advertise_message(dea_in_default_zone_with_2_instances_and_512m_memory)
            subject.find_dea(mem: 256, stack: "stack", app_id: "app-id").should == "dea-id4"
          end

          it "finds the DEA in user defined zones" do
            subject.process_advertise_message(dea_in_user_defined_zone_with_3_instances_and_1024m_memory)
            subject.process_advertise_message(dea_in_user_defined_zone_with_2_instances_and_1024m_memory)
            subject.find_dea(mem: 1, stack: "stack", app_id: "app-id").should == "dea-id6"
          end
        end

        context "when the instance numbers of all zones are the same" do
          it "finds the only one DEA with the smallest instance number" do
            subject.process_advertise_message(dea_in_default_zone_with_1_instance_and_128m_memory)
            subject.process_advertise_message(dea_in_default_zone_with_2_instances_and_512m_memory)
            subject.process_advertise_message(dea_in_user_defined_zone_with_3_instances_and_1024m_memory)
            subject.find_dea(mem: 1, stack: "stack", app_id: "app-id").should == "dea-id1"
          end

          it "finds the only one DEA with enough memory" do
            subject.process_advertise_message(dea_in_default_zone_with_1_instance_and_128m_memory)
            subject.process_advertise_message(dea_in_default_zone_with_2_instances_and_512m_memory)
            subject.process_advertise_message(dea_in_user_defined_zone_with_3_instances_and_1024m_memory)
            subject.find_dea(mem: 256, stack: "stack", app_id: "app-id").should == "dea-id4"
          end

          it "finds one of the DEAs with the smallest instance number" do
            subject.process_advertise_message(dea_in_default_zone_with_1_instance_and_128m_memory)
            subject.process_advertise_message(dea_in_default_zone_with_2_instances_and_512m_memory)
            subject.process_advertise_message(dea_in_user_defined_zone_with_2_instances_and_1024m_memory)
            subject.process_advertise_message(dea_in_user_defined_zone_with_1_instance_and_512m_memory)
            ["dea-id1","dea-id7"].should include (subject.find_dea(mem: 1, stack: "stack", app_id: "app-id"))
          end
        end

        context "when the instance numbers of all zones are different" do
          it "picks the only one DEA in the zone with fewest instances" do
            subject.process_advertise_message(dea_in_default_zone_with_1_instance_and_128m_memory)
            subject.process_advertise_message(dea_in_default_zone_with_2_instances_and_512m_memory)
            subject.process_advertise_message(dea_in_user_defined_zone_with_3_instances_and_1024m_memory)
            subject.process_advertise_message(dea_in_user_defined_zone_with_2_instances_and_1024m_memory)
            subject.find_dea(mem: 1, stack: "stack", app_id: "app-id").should == "dea-id1"
          end

          it "picks one of the DEAs in the zone with fewest instances" do
            subject.process_advertise_message(dea_in_default_zone_with_1_instance_and_128m_memory)
            subject.process_advertise_message(dea_in_default_zone_with_2_instances_and_512m_memory)
            subject.process_advertise_message(dea_in_user_defined_zone_with_1_instance_and_512m_memory)
            subject.process_advertise_message(dea_in_user_defined_zone_with_1_instance_and_256m_memory)

            ["dea-id7","dea-id8"].should include (subject.find_dea(mem: 1, stack: "stack", app_id: "app-id"))
          end

          it "picks the only DEA with enough resource even it has more instances" do
            subject.process_advertise_message(dea_in_default_zone_with_1_instance_and_128m_memory)
            subject.process_advertise_message(dea_in_default_zone_with_2_instances_and_512m_memory)
            subject.process_advertise_message(dea_in_user_defined_zone_with_3_instances_and_1024m_memory)
            subject.find_dea(mem: 768, stack: "stack", app_id: "app-id").should == "dea-id5"
          end

          it "picks DEA in zone with fewest instances even if other zones have more filtered DEAs" do
            subject.process_advertise_message(dea_in_default_zone_with_2_instances_and_128m_memory)
            subject.process_advertise_message(dea_in_default_zone_with_1_instance_and_512m_memory)
            subject.process_advertise_message(dea_in_user_defined_zone_with_2_instances_and_1024m_memory)
            subject.find_dea(mem: 256, stack: "stack", app_id: "app-id").should == "dea-id6"
          end
        end
      end

      describe "only_in_featured_dea" do
        context "when only considering dea features" do
          dea_feature_options = {
              'org_1' => {
                  'space_1' => {
                      'ssd' => true,
                      'security' => true
                  },
                  'space_2' => {
                      'ssd' => true,
                      'security' => false
                  },
                  'space_3' => {
                      'security' => false
                  }

              },
              'org_2' => {
                  'space_1' => {
                      'ssd' => true,
                      'security' => true
                  },
                  'space_2' => {
                      'ssd' => false,
                      'security' => false
                  }
              }
          }
          it 'picks the dea with expected feature' do
            subject.process_advertise_message(dea_with_ssd_and_security)
            subject.process_advertise_message(dea_with_ssd_but_no_security)

            subject.find_dea(mem: 256, stack: "stack", app_id: "app-id", dea_feature_options: dea_feature_options, app_org: 'org_1',
                             app_space: 'space_1').should == "dea-id-9"
            subject.find_dea(mem: 256, stack: "stack", app_id: "app-id", dea_feature_options: dea_feature_options, app_org: 'org_1',
                             app_space: 'space_2').should == "dea-id-10"
            subject.find_dea(mem: 256, stack: "stack", app_id: "app-id", dea_feature_options: dea_feature_options, app_org: 'org_2',
                             app_space: 'space_1').should == "dea-id-9"
          end
          it 'still picks the right dea when app requires no dea features' do
            subject.process_advertise_message(dea_with_ssd_and_security)
            subject.process_advertise_message(dea_with_ssd_but_no_security)
            subject.find_dea(mem: 256, stack: "stack", app_id: "app-id", dea_feature_options: dea_feature_options, app_org: 'org_3',
                             app_space: 'space_3').should be_in("dea-id-9", "dea-id-10")
          end
          it 'still works even when dea_feature_options is not provided ' do
            subject.process_advertise_message(dea_with_ssd_and_security)
            subject.process_advertise_message(dea_with_ssd_but_no_security)
            subject.find_dea(mem: 256, stack: "stack", app_id: "app-id", app_org: 'org_no',
                             app_space: 'space_no').should be_in("dea-id-9", "dea-id-10")
          end
          it 'picks no dea when dea features are not meet ' do
            subject.process_advertise_message(dea_with_ssd_and_security)
            subject.process_advertise_message(dea_with_ssd_but_no_security)
            subject.find_dea(mem: 256, stack: "stack", app_id: "app-id", dea_feature_options: dea_feature_options, app_org: 'org_2',
                             app_space: 'space_2').should == nil
          end
          it 'picks dea with two or three features but provide only two conditions from cc' do
            subject.process_advertise_message(dea_with_ssd_no_security_and_no_ha)
            subject.process_advertise_message(dea_with_ssd_and_security)
            subject.find_dea(mem: 256, stack: "stack", app_id: "app-id", dea_feature_options: dea_feature_options, app_org: 'org_1',
                             app_space: 'space_3').should == "dea-id-13"
          end
        end

        context "considering dea features and placement zone" do
          it 'picks the dea with expected feature and less instance count' do
            subject.process_advertise_message(dea_with_ssd_but_no_security_1_instance)
            subject.process_advertise_message(dea_with_ssd_but_no_security_2_instance)
            dea_feature_options = {
                'org_1' => {
                    'space_1' => {
                        'ssd' => true,
                        'security' => false
                    }
                },
            }
            subject.find_dea(mem: 256, stack: "stack", app_id: "app-id", dea_feature_options: dea_feature_options, app_org: 'org_1',
                             app_space: 'space_1').should == "dea-id-11"
          end
        end
      end

      describe "dea advertisement expiration (10sec)" do
        it "only finds deas with that have not expired" do
          Timecop.freeze do
            subject.process_advertise_message(dea_advertise_msg)

            Timecop.travel(9)
            subject.find_dea(mem: 1024, stack: "stack", app_id: "app-id").should == "dea-id"

            Timecop.travel(2)
            subject.find_dea(mem: 1024, stack: "stack", app_id: "app-id").should be_nil
          end
        end
      end

      describe "memory capacity" do
        it "only finds deas that can satisfy memory request" do
          subject.process_advertise_message(dea_advertise_msg)
          subject.find_dea(mem: 1025, stack: "stack", app_id: "app-id").should be_nil
          subject.find_dea(mem: 1024, stack: "stack", app_id: "app-id").should == "dea-id"
        end
      end

      describe "disk capacity" do
        context "when the disk capacity is not available" do
          let(:available_disk) { 0 }
          it "it doesn't find any deas" do
            subject.process_advertise_message(dea_advertise_msg)
            subject.find_dea(mem: 1024, disk: 10, stack: "stack", app_id: "app-id").should be_nil
          end
        end

        context "when the disk capacity is available" do
          let(:available_disk) { 50 }
          it "finds the DEA" do
            subject.process_advertise_message(dea_advertise_msg)
            subject.find_dea(mem: 1024, disk: 10, stack: "stack", app_id: "app-id").should == "dea-id"
          end
        end
      end

      describe "stacks availability" do
        it "only finds deas that can satisfy stack request" do
          subject.process_advertise_message(dea_advertise_msg)
          subject.find_dea(mem: 0, stack: "unknown-stack", app_id: "app-id").should be_nil
          subject.find_dea(mem: 0, stack: "stack", app_id: "app-id").should == "dea-id"
        end
      end

      describe "existing apps on the instance" do
        before do
          subject.process_advertise_message(dea_advertise_msg)
          subject.process_advertise_message(dea_advertise_msg.merge(
            "id" => "other-dea-id",
            "app_id_to_count" => {
              "app-id" => 1
            }
          ))
        end

        it "picks DEAs that have no existing instances of the app" do
          subject.find_dea(mem: 1, stack: "stack", app_id: "app-id").should == "dea-id"
          subject.find_dea(mem: 1, stack: "stack", app_id: "other-app-id").should == "other-dea-id"
        end
      end

      context "DEA randomization" do
        before do
          # Even though this fake DEA has more than enough memory, it should not affect results
          # because it already has an instance of the app.
          subject.process_advertise_message(
            dea_advertise_msg.merge("id" => "dea-id-already-has-an-instance",
                                    "available_memory" => 2048,
                                    "app_id_to_count" => { "app-id" => 1 })
          )
        end
        context "when all DEAs have the same available memory" do
          before do
            subject.process_advertise_message(dea_advertise_msg.merge("id" => "dea-id1"))
            subject.process_advertise_message(dea_advertise_msg.merge("id" => "dea-id2"))
          end

          it "randomly picks one of the eligible DEAs" do
            found_dea_ids = []
            20.times do
              found_dea_ids << subject.find_dea(mem: 1, stack: "stack", app_id: "app-id")
            end

            found_dea_ids.uniq.should =~ %w(dea-id1 dea-id2)
          end
        end

        context "when DEAs have different amounts of available memory" do
          before do
            subject.process_advertise_message(
              dea_advertise_msg.merge("id" => "dea-id1", "available_memory" => 1024)
            )
            subject.process_advertise_message(
              dea_advertise_msg.merge("id" => "dea-id2", "available_memory" => 1023)
            )
          end

          context "and there are only two DEAs" do
            it "always picks the one with the greater memory" do
              found_dea_ids = []
              20.times do
                found_dea_ids << subject.find_dea(mem: 1, stack: "stack", app_id: "app-id")
              end

              found_dea_ids.uniq.should =~ %w(dea-id1)
            end
          end

          context "and there are many DEAs" do
            before do
              subject.process_advertise_message(
                dea_advertise_msg.merge("id" => "dea-id3", "available_memory" => 1022)
              )
              subject.process_advertise_message(
                dea_advertise_msg.merge("id" => "dea-id4", "available_memory" => 1021)
              )
              subject.process_advertise_message(
                dea_advertise_msg.merge("id" => "dea-id5", "available_memory" => 1020)
              )
            end

            it "always picks from the half of the list (rounding up) with greater memory" do
              found_dea_ids = []
              40.times do
                found_dea_ids << subject.find_dea(mem: 1, stack: "stack", app_id: "app-id")
              end

              found_dea_ids.uniq.should =~ %w(dea-id1 dea-id2 dea-id3)
            end
          end
        end
      end

      describe "multiple instances of an app" do
        before do
          subject.process_advertise_message({
            "id" => "dea-id1",
            "stacks" => ["stack"],
            "available_memory" => 1024,
            "app_id_to_count" => {}
          })

          subject.process_advertise_message({
            "id" => "dea-id2",
            "stacks" => ["stack"],
            "available_memory" => 1024,
            "app_id_to_count" => {}
          })
        end

        it "will use different DEAs when starting an app with multiple instances" do
          dea_ids = []
          10.times do
            dea_id = subject.find_dea(mem: 0, stack: "stack", app_id: "app-id")
            dea_ids << dea_id
            subject.mark_app_started(dea_id: dea_id, app_id: "app-id")
          end

          dea_ids.should match_array((["dea-id1", "dea-id2"] * 5))
        end
      end

      describe "changing advertisements for the same dea" do
        it "only uses the newest message from a given dea" do
          Timecop.freeze do
            advertisement = dea_advertise_msg.merge("app_id_to_count" => {"app-id" => 1})
            subject.process_advertise_message(advertisement)

            Timecop.travel(5)

            next_advertisement = advertisement.dup
            next_advertisement["available_memory"] = 0
            subject.process_advertise_message(next_advertisement)

            subject.find_dea(mem: 64, stack: "stack", app_id: "foo").should be_nil
          end
        end
      end
    end

    describe "#reserve_app_memory" do
      let(:dea_advertise_msg) do
        {
            "id" => "dea-id",
            "stacks" => ["stack"],
            "available_memory" => 1024,
            "app_id_to_count" => { "old_app" => 1 }
        }
      end

      let(:new_dea_advertise_msg) do
        {
            "id" => "dea-id",
            "stacks" => ["stack"],
            "available_memory" => 1024,
            "app_id_to_count" => { "foo" => 1 }
        }
      end

      it "decrement the available memory based on app's memory" do
        subject.process_advertise_message(dea_advertise_msg)
        expect {
          subject.reserve_app_memory("dea-id", 1)
        }.to change {
          subject.find_dea(mem: 1024, stack: "stack", app_id: "foo")
        }.from("dea-id").to(nil)
      end

      it "update the available memory when next time the dea's ad arrives" do
        subject.process_advertise_message(dea_advertise_msg)
        subject.reserve_app_memory("dea-id", 1)
        expect {
          subject.process_advertise_message(new_dea_advertise_msg)
        }.to change {
          subject.find_dea(mem: 1024, stack: "stack", app_id: "foo")
        }.from(nil).to("dea-id")
      end
    end
  end
end
