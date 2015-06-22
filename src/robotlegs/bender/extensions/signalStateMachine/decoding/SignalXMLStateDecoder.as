package robotlegs.bender.extensions.signalStateMachine.decoding
{
    import org.osflash.signals.ISignal;
    import org.osflash.signals.Signal;
    import org.osflash.statemachine.base.BaseXMLStateDecoder;
    import org.osflash.statemachine.core.IState;
    import org.osflash.statemachine.errors.StateDecodeError;
    
    import robotlegs.bender.extensions.signalCommandMap.api.ISignalCommandMap;
    import robotlegs.bender.extensions.signalStateMachine.api.ISignalState;
    import robotlegs.bender.extensions.signalStateMachine.signals.Cancelled;
    import robotlegs.bender.extensions.signalStateMachine.signals.Entered;
    import robotlegs.bender.extensions.signalStateMachine.signals.EnteringGuard;
    import robotlegs.bender.extensions.signalStateMachine.signals.ExitingGuard;
    import robotlegs.bender.extensions.signalStateMachine.signals.TearDown;
    import robotlegs.bender.extensions.signalStateMachine.states.SignalState;
    import robotlegs.bender.extensions.signalStateMachine.transitioning.TransitionPhase;
    import robotlegs.bender.framework.api.IInjector;

    /**
     * A StateDecoder is used by the FSMInjector to encapsulate the decoding of a
     * state declaration into a concrete IState instance.
     *
     * This implementation converts an XML declaration into an ISignalState, it also
     * is the point where the DI takes place, and thus where all the Robotleg
     * dependencies are encapsulated.
     *
     * @see org.osflash.statemachine.FSMInjector
     * @see org.osflash.statemachine.core.ISignalState
     * @see org.osflash.statemachine.states.SignalState
     */
    public class SignalXMLStateDecoder extends BaseXMLStateDecoder
    {
        public static const COMMAND_CLASS_CAN_BE_MAPPED_ONCE_ONLY_TO_SAME_SIGNAL:String = "A command class can be mapped once only to the same signal: ";

        public static const COMMAND_CLASS_NOT_REGISTERED:String = "These commands need to be added to the StateDecoder: ";

        /**
         * @private
         */
        protected var classBagMap:Array;

        protected var errors:Array;

        /**
         * @private
         */
        protected var injector:IInjector;

        /**
         * @private
         */
        protected var signalCommandMap:ISignalCommandMap;

        /**
         * Creates an instance of a SignalXMLStateDecoder
         * @param fsm the state declaration
         * @param injector the injector for the current IContext
         * @param signalCommandMap the ISignalCommandMap for the current IContext
         */
        public function SignalXMLStateDecoder(fsm:XML, injector:IInjector, signalCommandMap:ISignalCommandMap):void
        {
            this.injector = injector;
            this.signalCommandMap = signalCommandMap;
            errors = [];
            super(fsm);
        }

        /**
         * Adds a command Class reference.
         *
         * Any command declared in the state declaration must be added here.
         * @param value the command class
         * @return whether the command class has been add successfully
         */
        public function addClass(value:Class):Boolean
        {
            if (classBagMap == null)
            {
                classBagMap = [];
            }

            if (hasClass(value))
            {
                return false;
            }

            classBagMap.push(new ClassBag(value));
            return true;
        }

        /**
         * @inheritDoc
         */
        override public final function decodeState(stateDef:Object):IState
        {
            // Create State object
            var state:ISignalState = getState(stateDef);
            decodeTransitions(state, stateDef);
            injectState(state, stateDef);
            mapSignals(state, stateDef);
            return state;
        }

        /**
         * @inheritDoc
         */
        override public function destroy():void
        {
            errors = null;
            injector = null;
            signalCommandMap = null;
            if (classBagMap != null)
            {
                for each (var cb:ClassBag in classBagMap)
                {
                    cb.destroy();
                }
            }
            classBagMap = null;
            super.destroy();
        }

        /**
         * Retrieves a command class registered with the addCommandClass method
         * @param name this can either be the name, the fully qualified name or an instance of the Class
         * @return the class reference
         */
        public function getClass(name:Object):Class
        {
            for each (var cb:ClassBag in classBagMap)
            {
                if (cb.equals(name))
                {
                    return cb.payload;
                }
            }
            return null;
        }

        /**
         * Test to determine whether a particular class has already been added
         * to the decoder
         * @param name this can either be the name, the fully qualified name or an instance of the Class
         * @return
         */
        public function hasClass(name:Object):Boolean
        {
            return (getClass(name) != null);
        }

        /**
         * Decodes the State's transitions from the state declaration
         * @param state the state into which to inject the transitions
         * @param stateDef the state's declaration
         */
        protected function decodeTransitions(state:IState, stateDef:Object):void
        {
            var transitions:XMLList = stateDef..transition as XMLList;
            for (var i:int; i < transitions.length(); i++)
            {
                var transDef:XML = transitions[i];
                state.defineTrans(String(transDef.@action), String(transDef.@target));
            }
        }

        /**
         * Factory method for creating concrete ISignalState. Override this to allow for the
         * creation of custom states
         * @param stateDef the declaration for a single state
         * @return an instance of the state described in the data
         */
        protected function getState(stateDef:Object):ISignalState
        {			
            var signalName:String = stateDef.@name.toString();
            return new SignalState(
                signalName,
                stateDef.entered.length() != 0	 		? this.getSignal(Entered, signalName) : null,
                stateDef.enteringGuard.length() != 0 	? this.getSignal(EnteringGuard, signalName) : null,
                stateDef.exitingGuard.length() != 0 	? this.getSignal(ExitingGuard, signalName) : null,
                stateDef.tearDown.length() != 0 		? this.getSignal(TearDown, signalName) : null,
                stateDef.cancelled.length() != 0 		? this.getSignal(Cancelled, signalName) : null
                );
/*            return new SignalState(
                signalName,
                stateDef.entered != null ? this.getSignal(Entered, signalName) : null,
                stateDef.enteringGuard != null ? this.getSignal(EnteringGuard, signalName) : null,
                stateDef.exitingGuard != null ? this.getSignal(ExitingGuard, signalName) : null,
                stateDef.tearDown != null ? this.getSignal(TearDown, signalName) : null,
                stateDef.cancelled != null ? this.getSignal(Cancelled, signalName) : null
                );*/
        }

        /**
         * Injects a IState into the DI Container if it is marked for injection in its declaration
         * @param state the IState to be injected
         * @param stateDef the state's declaration
         */
        protected function injectState(state:IState, stateDef:Object):void
        {
            var inject:Boolean = (stateDef.@inject.toString() == "true");
            if (inject)
            {
                this.injector.map(ISignalState, state.name).toValue(state);
            }
        }

        /**
         * Maps the commands referenced in the state declaration to their appropriate
         * state transition phases
         * @param signalState the state whose ISignal phases are to be mapped to
         * @param stateDef the state's declaration
         */
        protected function mapSignals(signalState:ISignalState, stateDef:Object):void
        {

            var entered:PhaseDecoder = new PhaseDecoder(TransitionPhase.ENTERED, stateDef.entered);
            var enteringGuard:PhaseDecoder = new PhaseDecoder(TransitionPhase.ENTERING_GUARD, stateDef.enteringGuard);
            var exitingGuard:PhaseDecoder = new PhaseDecoder(TransitionPhase.EXITING_GUARD, stateDef.exitingGuard);
            var tearDown:PhaseDecoder = new PhaseDecoder(TransitionPhase.TEAR_DOWN, stateDef.tearDown);
            var cancelled:PhaseDecoder = new PhaseDecoder(TransitionPhase.CANCELLED, stateDef.cancelled);

            if (!entered.isNull)
            {
                this.mapSignalCommand(signalState.name, Entered, entered);
            }

            if (!enteringGuard.isNull)
            {
                this.mapSignalCommand(signalState.name, EnteringGuard, enteringGuard);
            }

            if (!exitingGuard.isNull)
            {
                this.mapSignalCommand(signalState.name, ExitingGuard, exitingGuard);
            }

            if (!tearDown.isNull)
            {
                this.mapSignalCommand(signalState.name, TearDown, tearDown);
            }

            if (!cancelled.isNull)
            {
                this.mapSignalCommand(signalState.name, Cancelled, cancelled);
            }

            if (errors.length > 0)
            {
                throw new StateDecodeError(COMMAND_CLASS_NOT_REGISTERED + errors.toString());
            }
        }

        private function getAndValidateClass(name:Object):Class
        {
            var c:Class = getClass(name);
            if (c == null)
            {
                errors.push(name.toString());
            }
            return c;
        }

        private function getSignal(signalClass:Class, signalName:String = ""):Signal
        {
            if (!this.injector.hasMapping(signalClass, signalName))
            {
                this.injector.map(signalClass, signalName).asSingleton();
            }
            return this.injector.getInstance(signalClass, signalName);
        }

        private function mapGuardedSignalCommand(stateName:String, signalClass:Class, item:PhaseDecoderItem):void
        {
            var guardClasses:Array = [];
            var commandClass:Class = getAndValidateClass(item.commandClassName);

            for each (var guardClassName:String in item.guardCommandClassNames)
            {
                var g:Class = getAndValidateClass(guardClassName);
                if (g != null)
                {
                    guardClasses.push(g);
                }
            }

            if (guardClasses.length != item.guardCommandClassNames.length || commandClass == null)
            {
                return;
            }

            this.signalCommandMap.map(signalClass, stateName).toCommand(commandClass).withGuards(guardClasses);
//            this.signalCommandMap.map(signalClass).toCommand(commandClass).withGuards(guardClasses);
        }

        private function mapSignalCommand(stateName:String, signalClass:Class, phaseDecoder:PhaseDecoder):void
        {
            for each (var item:PhaseDecoderItem in phaseDecoder.decodedItems)
            {
                if (item.isError)
                {
                    throw new StateDecodeError(item.error);
                }
                else if (item.guardCommandClassNames == null)
                {
                    var commandClass:Class = getAndValidateClass(item.commandClassName);
                    if (commandClass != null)
                    {
                        this.signalCommandMap.map(signalClass, stateName).toCommand(commandClass);
//                        this.signalCommandMap.map(signalClass).toCommand(commandClass);
                    }
                }
                else
                {
                    mapGuardedSignalCommand(stateName, signalClass, item)
                }

            }
        }
    }
}

import flash.utils.describeType;

import org.osflash.statemachine.core.ITransitionPhase;

import robotlegs.bender.extensions.signalStateMachine.api.IClassBag;
import robotlegs.bender.extensions.signalStateMachine.transitioning.TransitionPhase;

/**
 * Wrapper class for a Class reference.
 */
internal class ClassBag implements IClassBag
{

    private var _name:String;

    private var _payload:Class;

    private var _pkg:String;

    /**
     * Wraps and reflects a class reference instance )
     */
    public function ClassBag(c:Class):void
    {
        _payload = c;
        describeClass(c);
    }

    /**
     * Destroys the ClassBag
     */
    public function destroy():void
    {
        _payload = null;
        _name = null;
        _pkg = null;
    }

    /**
     * @inheritDoc
     */
    public function equals(value:Object):Boolean
    {
        return ((value.toString() == _pkg + "." + _name) ||
            (value.toString() == _pkg + "::" + _name) ||
            (value.toString() == _name) ||
            (value == _payload));
    }

    /**
     * @inheritDoc
     */
    public function get name():String
    {
        return _name;
    }

    /**
     * @inheritDoc
     */
    public function get payload():Class
    {
        return _payload;
    }

    /**
     * @inheritDoc
     */
    public function get pkg():String
    {
        return _pkg;
    }

    /**
     * @inheritDoc
     */
    public function toString():String
    {
        return _pkg + "." + _name;
    }

    /**
     * @private
     */
    private function describeClass(c:Class):void
    {
        var description:XML = describeType(c);
        var split:Array = description.@name.toString().split("::");
        _pkg = String(split[0]);
        _name = String(split[1]);
    }
}

internal class PhaseDecoder
{

    internal var decodedItems:Array;

    private var _phase:ITransitionPhase;

    public function PhaseDecoder(phase:ITransitionPhase, phaseDef:XMLList):void
    {
        _phase = phase;
        decode(phaseDef);
    }

    public function get isNull():Boolean
    {
        return (decodedItems == null || decodedItems.length == 0);
    }

    private function decode(phaseDef:XMLList):void
    {
        if (phaseDef.length() == 0)
        {
            return;
        }
        decodedItems = [];
        var list:XMLList = phaseDef.commandClass;
        for each (var xml:XML in list)
        {
            var item:PhaseDecoderItem = new PhaseDecoderItem();
            item.phase = _phase;
            item.commandClassName = xml.@classPath.toString();
            item.guardCommandClassNames = decodeGuards(xml.guardClass.@classPath);
            decodedItems.push(item);
        }
    }


    private function decodeGuards(list:XMLList):Array
    {
        if (list.length() == 0)
        {
            return null;
        }
        var a:Array = [];
        for each (var xml:XML in list)
        {
            a.push(xml.toString());
        }
        return a;
    }
}

internal class PhaseDecoderItem
{

    internal var commandClassName:String;

    internal var error:String;

    internal var guardCommandClassNames:Array;

    internal var phase:ITransitionPhase;

    public function get isError():Boolean
    {
        if (TransitionPhase.ENTERED.equals(phase) || TransitionPhase.TEAR_DOWN.equals(phase) || 
			TransitionPhase.CANCELLED.equals(phase) || TransitionPhase.ENTERING_GUARD.equals(phase) 
			|| TransitionPhase.EXITING_GUARD.equals(phase))
        {
            return false;
        }

        return true;
    }
}
