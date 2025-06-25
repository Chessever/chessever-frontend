##Generate Debug SHA :

Debug SHA

   ```
keytool -list -v \
-alias androiddebugkey \
-keystore ~/.android/debug.keystore \
-storepass android \
-keypass android
   ```

##Generate Debug SHA :
Place the my-release-key.jks in

   ```
your-project/android/app/src/my-release-key.jks
   ```

directory

and place key.properties in :

   ```      
your-project/android/key.properties
   ```

run :

   ```
keytool -list -v \
-keystore ~/android/app/src/my-release-key.jks \
-alias my-key-alias
   ```

from your project directory using terminal