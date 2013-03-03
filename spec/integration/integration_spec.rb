require 'spec_helper'
require 'integration/models/vehicle'

describe Vehicle do
  let(:vehicle) { Vehicle.new }
  subject { vehicle }

  its(:passed_inspection?) { should be_false }

  shared_examples 'crashable' do
    describe 'crash' do
      context 'having passed inspection' do
        before { vehicle.stub(:passed_inspection).and_return(true) }
        pending 'keeps running' do
          initial_state = vehicle.state
          vehicle.crash!

          vehicle.state.should eq initial_state
        end
      end

      context 'not having passed inspection' do
        before { vehicle.stub(:passed_inspection).and_return(false) }
        it 'stalls' do
          vehicle.crash!
          vehicle.state.should eq :stalled.to_s
        end
      end
    end
  end

  shared_examples 'speedless' do
    it 'does not respond to speed' do
      expect { vehicle.speed }.to raise_error NoMethodError
    end
  end

  describe '#initialize' do
    its(:seatbelt_on) { should be_false }
    its(:time_used) { should eq 0 }
    its(:auto_shop_busy) { should be_true }
  end

  describe '#put_on_seatbelt' do
    it 'sets seatbelt_on to true' do
      vehicle.seatbelt_on = false
      vehicle.put_on_seatbelt

      vehicle.seatbelt_on.should be_true
    end
  end

  describe 'state machine' do
    it { should have_states :state, :parked, :idling, :stalled,
                            :first_gear, :second_gear, :third_gear }

    it 'has an initial state of "parked"' do
      vehicle.should be_parked
    end

    it 'has an initial alarm state of "active"' do
      vehicle.alarm_active?.should be_true
    end

    describe 'around transitions' do
      it 'updates the time used' do
        vehicle.should_receive(:time_used=).with(0)
        Timecop.freeze { vehicle.ignite! }
      end
    end

    context 'when parked' do
      before { vehicle.state = :parked.to_s }

      it { should respond_to_event :ignite }
      it { should_not respond_to_events :park, :idle, :shift_up,
                                        :shift_down, :crash, :repair }

      its(:speed) { should be_zero }
      it { should_not be_moving }

      describe 'before transitions' do
        it 'puts on a seatbelt' do
          vehicle.should_receive :put_on_seatbelt
          vehicle.ignite!
        end
      end

      describe 'ignite' do
        it 'should transition to idling' do
          vehicle.ignite!
          vehicle.should be_idling
        end
      end
    end

    context 'when transitioning to parked' do
      before { vehicle.state = :idling.to_s }
      it 'removes seatbelts' do
        vehicle.should_receive(:seatbelt_on=).with(false)
        vehicle.park!
      end
    end

    context 'when idling' do
      before { vehicle.state = :idling.to_s }

      it { should respond_to_events :park, :shift_up, :crash }
      it { should_not respond_to_events :ignite, :idle, :shift_down, :repair }

      its(:speed) { should eq 10 }
      it { should_not be_moving }

      describe 'park' do
        it 'should transition to a parked state' do
          vehicle.park!
          vehicle.should be_parked
        end
      end

      describe 'shift up' do
        it 'should shift into first gear' do
          vehicle.shift_up!
          vehicle.should be_first_gear
        end
      end

      it_behaves_like 'crashable'
    end

    context 'when stalled' do
      before { vehicle.state = :stalled.to_s }

      it { should respond_to_events :ignite, :repair }
      it { should_not respond_to_events :park, :idle, :shift_up,
                                        :shift_down, :crash }

      it { should_not be_moving }
      it_behaves_like 'speedless'

      describe 'ignite' do
        it 'remains stalled' do
          vehicle.ignite!
          vehicle.should be_stalled
        end
      end

      describe 'repair' do
        context 'the auto shop is busy' do
          before { vehicle.stub(:auto_shop_busy).and_return(true) }
          it 'remains stalled' do
            vehicle.repair!
            vehicle.should be_stalled
          end
        end

        context 'the auto shop is not busy' do
          before { vehicle.stub(:auto_shop_busy).and_return(false) }
          it 'is parked' do
            vehicle.repair!
            vehicle.should be_parked
          end
        end
      end
    end

    context 'when in first gear' do
      before { vehicle.state = :first_gear.to_s }

      it { should respond_to_events :park, :idle, :shift_up, :crash }
      it { should_not respond_to_events :ignite, :shift_down, :repair }

      its(:speed) { should eq 10 }
      it { should be_moving }

      describe 'park' do
        it 'parks' do
          vehicle.park!
          vehicle.should be_parked
        end
      end

      describe 'idle' do
        it 'idles' do
          vehicle.idle!
          vehicle.should be_idling
        end
      end

      describe 'shift up' do
        it 'shift into second gear' do
          vehicle.shift_up!
          vehicle.should be_second_gear
        end
      end

      it_behaves_like 'crashable'
    end

    context 'when in second gear' do
      before { vehicle.state = :second_gear.to_s }

      it { should respond_to_events :shift_up, :shift_down, :crash }
      it { should_not respond_to_events :park, :ignite, :idle, :repair  }

      it { should be_moving }
      it_behaves_like 'speedless'

      describe 'shift up' do
        it 'shifts into third gear' do
          vehicle.shift_up!
          vehicle.should be_third_gear
        end
      end

      describe 'shift down' do
        it 'shifts back into first gear' do
          vehicle.shift_down!
          vehicle.should be_first_gear
        end
      end

      it_behaves_like 'crashable'
    end

    context 'when in third gear' do
      before { vehicle.state = :third_gear.to_s }

      it { should respond_to_events :shift_down, :crash }
      it { should_not respond_to_events :park, :ignite, :idle,
                                        :shift_up, :repair }

      it { should be_moving }
      it_behaves_like 'speedless'

      describe 'shift down' do
        it 'shifts back into second gear' do
          vehicle.shift_down!
          vehicle.should be_second_gear
        end
      end

      it_behaves_like 'crashable'
    end

    context 'on ignition' do
      context 'when it fails' do
        before { vehicle.stub(:ignite).and_return(false) }
        pending 'logs the failure' do
          vehicle.should_receive(:log_start_failure)
          vehicle.ignite
        end
      end
    end

    context 'on a crash' do
      before { vehicle.state = :third_gear.to_s }
      it 'gets towed' do
        vehicle.should_receive(:tow)
        vehicle.crash!
      end
    end

    context 'upon being repaired' do
      before { vehicle.state = :stalled.to_s }
      it 'gets fixed' do
        vehicle.should_receive(:fix)
        vehicle.repair!
      end
    end
  end

  describe 'alarm state machine' do
    it { should have_state :alarm_state, :active, value: 1 }
    it { should have_state :alarm_state, :off, value: 0 }

    it 'has an initial state of activated' do
      vehicle.alarm_active?.should be_true
    end

    context 'when active' do
      it { should respond_to_events :enable_alarm, :disable_alarm }

      describe 'enable' do
        it 'becomes active' do
          vehicle.enable_alarm!
          vehicle.alarm_active?.should be_true
        end
      end

      describe 'disable' do
        it 'turns the alarm off' do
          vehicle.disable_alarm!
          vehicle.alarm_off?.should be_true
        end
      end
    end

    context 'when off' do
      before { vehicle.alarm_state = 0 }

      it { should respond_to_events :enable_alarm, :disable_alarm }

      describe 'enable' do
        it 'becomes active' do
          vehicle.enable_alarm!
          vehicle.alarm_active?.should be_true
        end
      end

      describe 'disable' do
        it 'turns the alarm off' do
          vehicle.disable_alarm!
          vehicle.alarm_off?.should be_true
        end
      end
    end
  end
end