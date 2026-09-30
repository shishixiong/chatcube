import abilityTest from './Ability.test';
import kidsSubjectUtilsTest from './utils/KidsSubjectUtils.test';
import learningLedgerModelsTest from './utils/LearningLedgerModels.test';

export default function testsuite() {
  abilityTest();
  kidsSubjectUtilsTest();
  learningLedgerModelsTest();
}
